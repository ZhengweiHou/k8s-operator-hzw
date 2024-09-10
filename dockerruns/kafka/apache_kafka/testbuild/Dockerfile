FROM apache/kafka:3.7.0

USER root

COPY --chown=appuser:appuser run /etc/kafka/docker/run
COPY --chown=appuser:appuser configureDefaults /etc/kafka/docker/configureDefaults
COPY --chown=appuser:appuser configure /etc/kafka/docker/configure
COPY --chown=appuser:appuser launch /etc/kafka/docker/launch
COPY --chown=appuser:appuser kafka-run-class.sh /opt/kafka/bin/kafka-run-class.sh
COPY --chown=appuser:appuser kafka-server-start.sh /opt/kafka/bin/kafka-server-start.sh
