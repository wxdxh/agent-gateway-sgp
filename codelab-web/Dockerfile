FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY codelab-ko.html /usr/share/nginx/html/codelab-ko.html
COPY gdocs-paste.html /usr/share/nginx/html/gdocs-paste.html
COPY QWIKLABS_CLOUD_SHELL_KO.docx /usr/share/nginx/html/QWIKLABS_CLOUD_SHELL_KO.docx
COPY terraform.zip /usr/share/nginx/html/terraform.zip

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
