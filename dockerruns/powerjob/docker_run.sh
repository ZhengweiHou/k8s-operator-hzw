docker run -d \
 			 --restart=always \
       --name powerjob-server \
       -p 7700:7700 -p 10086:10086 -p 10010:10010 \
       -e TZ="Asia/Shanghai" \
       -e JVMOPTIONS="" \
       -e PARAMS="--spring.profiles.active=product --spring.datasource.core.jdbc-url=jdbc:mysql:/172.17.0.1/:3306/powerjob?useUnicode=true&characterEncoding=UTF-8 --spring.datasource.core.username=root --spring.datasource.core.password=root" \
       -v ~/docker/powerjob-server:/root/powerjob/server -v ~/.m2:/root/.m2 \
       powerjob/powerjob-server:latest
