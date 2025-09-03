FROM hugomods/hugo AS builder
WORKDIR /src
COPY ./blog/go.mod ./blog/hugo.toml ./
RUN rm -rf themes
RUN hugo mod get
COPY ./blog/ ./
RUN hugo --minify
FROM nginx:alpine
COPY --from=builder /src/public /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

