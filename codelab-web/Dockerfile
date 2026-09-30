FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY codelab-ko.html /usr/share/nginx/html/codelab-ko.html

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
