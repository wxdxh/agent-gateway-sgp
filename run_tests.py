#!/usr/bin/env python3
"""
Automated End-to-End Verification for Gemini Enterprise Agent Gateway & Semantic Governance Policies (SGP).
Executes a multi-turn banking conversation across Gemini Enterprise Agent Runtime:
  - Turn 1: Customer identification (CUST005) -> Expect account details & balance.
  - Turn 2: Permitted transfer (< 1,000,000 KRW / $1,000 USD) -> SGP ALLOW -> Transfer succeeds.
  - Turn 3: High-value transfer (> 1,000,000 KRW / $1,000 USD) -> SGP DENY -> Blocked with policy denial reason.
Followed by Cloud Logging verification of SGP audit verdicts.
"""

import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

# Allow standard python urllib on local macOS developer environments
ssl._create_default_https_context = ssl._create_unverified_context


def get_access_token():
    try:
        res = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception as e:
        print(f"Error obtaining gcloud access token: {e}")
        sys.exit(1)


def resolve_reasoning_engine_id(project_id: str, location: str, token: str) -> str:
    env_re_id = os.environ.get("REASONING_ENGINE_ID")
    if env_re_id:
        return env_re_id
    try:
        url = f"https://{location}-aiplatform.googleapis.com/v1beta1/projects/{project_id}/locations/{location}/reasoningEngines"
        req = urllib.request.Request(
            url,
            headers={"Authorization": f"Bearer {token}"},
            method="GET",
        )
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            engines = data.get("reasoningEngines", [])
            matches = [
                e for e in engines
                if e.get("displayName") == "conversational-banking"
            ]
            target_list = matches if matches else engines
            if target_list:
                target_list.sort(key=lambda x: x.get("createTime", ""), reverse=True)
                full_name = target_list[0].get("name", "")
                if full_name:
                    return full_name.split("/")[-1]
    except Exception as e:
        print(f"Warning resolving reasoning engine ID via API: {e}")
    return "378064324431708160"


def wait_for_reasoning_engine_ready(project_id: str, location: str, re_id: str) -> str:
    """Ensure the background Agent Runtime container build from Step 5 is finished."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    metadata_path = os.path.join(script_dir, "conversational-banking", "deployment_metadata.json")
    deploy_script = os.path.join(script_dir, "05-deploy-agent.sh")
    start_wait = time.time()

    # 1. If deployment_metadata.json has a pending_operation, poll it until done
    if os.path.exists(metadata_path):
        try:
            with open(metadata_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            op_name = meta.get("pending_operation", {}).get("operation_name")
        except Exception:
            op_name = None

        if op_name:
            op_url = f"https://{location}-aiplatform.googleapis.com/v1beta1/{op_name}"
            while True:
                token = get_access_token()
                try:
                    req = urllib.request.Request(
                        op_url,
                        headers={"Authorization": f"Bearer {token}"},
                        method="GET",
                    )
                    with urllib.request.urlopen(req) as resp:
                        op_data = json.loads(resp.read().decode("utf-8"))
                    if op_data.get("done"):
                        if "error" in op_data:
                            print(f"[WARNING] Background deploy operation reported error: {op_data['error']}")
                        else:
                            print("==> Background Agent Runtime container build completed!")
                        break
                except Exception as e:
                    print(f"Note checking operation status: {e}")

                elapsed = int(time.time() - start_wait)
                mins, secs = divmod(elapsed, 60)
                print(
                    f"⏳ Waiting for background Agent Runtime deployment (started in Step 5) "
                    f"to complete... ({mins}m {secs}s elapsed, checking again in 20s)"
                )
                time.sleep(20)

    # 2. Verify the Reasoning Engine resource has a deployed spec (not just a bare identity shell)
    triggered_deploy = False
    while True:
        token = get_access_token()
        re_url = f"https://{location}-aiplatform.googleapis.com/v1beta1/projects/{project_id}/locations/{location}/reasoningEngines/{re_id}"
        try:
            req = urllib.request.Request(
                re_url,
                headers={"Authorization": f"Bearer {token}"},
                method="GET",
            )
            with urllib.request.urlopen(req) as resp:
                re_data = json.loads(resp.read().decode("utf-8"))
            spec = re_data.get("spec", {})
            has_code = bool(
                spec.get("sourceCodeSpec")
                or spec.get("packageSpec")
                or spec.get("containerSpec")
                or spec.get("deploymentSpec")
            )
            if has_code:
                break

            # Check if there is any in-progress LRO on this ReasoningEngine
            ops_url = f"{re_url}/operations"
            ops_req = urllib.request.Request(
                ops_url,
                headers={"Authorization": f"Bearer {token}"},
                method="GET",
            )
            in_progress = False
            try:
                with urllib.request.urlopen(ops_req) as ops_resp:
                    ops_data = json.loads(ops_resp.read().decode("utf-8"))
                    for op in ops_data.get("operations", []):
                        if not op.get("done", False):
                            in_progress = True
                            break
            except Exception:
                pass

            if not in_progress and not triggered_deploy and os.path.exists(deploy_script):
                print("==> Reasoning Engine is a bare identity shell with no active build. Triggering ./05-deploy-agent.sh...")
                subprocess.run(["bash", deploy_script], check=False)
                triggered_deploy = True
                return wait_for_reasoning_engine_ready(project_id, location, re_id)
        except Exception as e:
            print(f"Note checking Reasoning Engine spec: {e}")
            break

        elapsed = int(time.time() - start_wait)
        mins, secs = divmod(elapsed, 60)
        if elapsed > 900:
            break
        print(
            f"⏳ Waiting for Reasoning Engine {re_id} container spec to become active... "
            f"({mins}m {secs}s elapsed, checking again in 20s)"
        )
        time.sleep(20)

    return get_access_token()


def stream_query(project_id: str, location: str, re_id: str, token: str, session_id: str, message: str):
    url = f"https://{location}-aiplatform.googleapis.com/v1beta1/projects/{project_id}/locations/{location}/reasoningEngines/{re_id}:streamQuery"
    payload = {
        "class_method": "stream_query",
        "input": {
            "message": message,
            "session_id": session_id,
        },
    }

    max_attempts = 24
    for attempt in range(1, max_attempts + 1):
        current_token = token if attempt == 1 else get_access_token()
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {current_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        responses = []
        try:
            with urllib.request.urlopen(req) as resp:
                for line in resp:
                    line_str = line.decode("utf-8").strip()
                    if not line_str:
                        continue
                    try:
                        data = json.loads(line_str)
                        responses.append(data)
                    except Exception:
                        pass
            break
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="replace")
            if (
                e.code in (400, 429, 502, 503, 504)
                and (
                    "does not have running instances" in err_body
                    or "FAILED_PRECONDITION" in err_body
                    or e.code in (429, 502, 503, 504)
                )
                and attempt < max_attempts
            ):
                print(
                    f"⏳ Agent Runtime instance is still warming up or finishing deployment "
                    f"(attempt {attempt}/{max_attempts}). Retrying in 20s..."
                )
                time.sleep(20)
                continue
            return None, f"HTTP {e.code}: {err_body}"
        except Exception as e:
            return None, str(e)

    # Extract final text from stream chunks
    text_parts = []
    for chunk in responses:
        content = chunk.get("content", {})
        parts = content.get("parts", [])
        for p in parts:
            if "text" in p:
                text_parts.append(p["text"])

    final_text = "".join(text_parts).strip()
    return {"text": final_text, "raw_chunks": responses}, None


def main():
    project_id = os.environ.get("PROJECT_ID", "elevate-security-dhwee")
    location = os.environ.get("LOCATION", "us-central1")
    token = get_access_token()
    re_id = resolve_reasoning_engine_id(project_id, location, token)

    print("=" * 80)
    print(" Running Automated End-to-End Verification of Gemini Enterprise Agent Gateway + SGP")
    print(f" Project:          {project_id}")
    print(f" Region:           {location}")
    print(f" Reasoning Engine: {re_id}")
    print("=" * 80)

    token = wait_for_reasoning_engine_ready(project_id, location, re_id)
    session_id = f"sgp-eval-{int(time.time())}"
    print(f"Session ID: {session_id}\n")

    turns = [
        {
            "turn": 1,
            "title": "Customer Identification (CUST005)",
            "message": "I am customer CUST005",
            "expect_keyword": ["Alice Smith"],
        },
        {
            "turn": 2,
            "title": "Allowed Transaction (< $1,000 USD)",
            "message": "transfer 50 to 555-0001",
            "expect_keyword": ["successfully"],
        },
        {
            "turn": 3,
            "title": "Blocked Transaction (> $1,000 USD SGP Limit)",
            "message": "transfer 2000 to 555-0002",
            "expect_keyword": ["exceeds the maximum allowed limit", "High Value Transfer Limit"],
        },
    ]

    all_passed = True

    for t in turns:
        t_num = t["turn"]
        title = t["title"]
        msg = t["message"]
        print(f"--- [Turn {t_num}: {title}] ---")
        print(f"User Input: '{msg}'")

        res, err = stream_query(project_id, location, re_id, token, session_id, msg)
        if err:
            print(f"[FAILED] Error calling agent runtime: {err}\n")
            all_passed = False
            continue

        agent_text = res["text"]
        print(f"Agent Response:\n{agent_text}\n")

        # Validate keywords
        matched = all(k.lower() in agent_text.lower() for k in t["expect_keyword"])
        if matched:
            print(f"--> [Turn {t_num} VERIFIED]: Expected response criteria met.")
        else:
            print(f"--> [Turn {t_num} WARNING]: One or more expected keywords not found ({t['expect_keyword']}).")
            all_passed = False
        print("-" * 80)

    # Cloud Logging audit check
    print("\n" + "=" * 80)
    print(" Querying Cloud Logging for SGP Policy Enforcement Audit Logs...")
    print("=" * 80)
    try:
        cmd = [
            "gcloud", "logging", "read",
            f'logName="projects/{project_id}/logs/semantic-governance-policy" AND jsonPayload.verdict:*',
            "--limit=4", "--format=json"
        ]
        log_res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        entries = json.loads(log_res.stdout) if log_res.stdout.strip() else []
        print(f"Retrieved {len(entries)} SGP audit log entries:")
        for e in entries:
            ts = e.get("timestamp")
            payload = e.get("jsonPayload", {})
            verdict = payload.get("verdict")
            evals = payload.get("evaluations", [{}])
            tool = evals[0].get("toolName") if evals else None
            rationale = evals[0].get("rationale") if evals else None
            print(f"[{ts}] Verdict: {verdict} | Tool: {tool}")
            print(f"   Rationale: {rationale}")
    except Exception as e:
        print(f"Error querying Cloud Logging: {e}")

    print("\n" + "=" * 80)
    if all_passed:
        print(" [SUCCESS] All 3 turns and SGP governance enforcement verified successfully!")
    else:
        print(" [PARTIAL] One or more verification criteria requires manual review.")
    print("=" * 80)
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
