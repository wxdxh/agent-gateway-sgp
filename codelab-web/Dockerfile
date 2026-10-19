FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY index.html /usr/share/nginx/html/codelab-ko.html
COPY img /usr/share/nginx/html/img

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
