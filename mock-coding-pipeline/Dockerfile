FROM alpine:latest
RUN apk add --no-cache bash curl
COPY mock-pipeline.sh /app/pipeline.sh
RUN chmod +x /app/pipeline.sh
CMD ["/app/pipeline.sh"]
