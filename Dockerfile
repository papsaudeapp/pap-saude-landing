FROM nginxinc/nginx-unprivileged:1.29-alpine
ARG VCS_REF
LABEL org.opencontainers.image.source="https://github.com/papsaudeapp/pap-saude-landing" \
      org.opencontainers.image.revision="${VCS_REF}"
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chown=101:101 site/ /usr/share/nginx/html/
USER 101:101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=4s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
