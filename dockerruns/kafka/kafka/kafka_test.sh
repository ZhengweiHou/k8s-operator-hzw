docker exec -it kafka /bin/sh

cd opt/kafka/bin

# create topic
kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic hzwkfk

# start producer
kafka-console-producer.sh --broker-list localhost:9092 --topic hzwkfk

# start consumer
kafka-console-consumer.sh --from-beginning --bootstrap-server localhost:9092 --topic hzwkfk



