docker run \
-d \
-p 8443:443 \
-p 8090:80 \
--name gitlab \
-v ~/rundata/data_gitlab/etc:/etc/gitlab \
-v ~/rundata/data_gitlab/log:/var/log/gitlab \
-v ~/rundata/data_gitlab/data:/var/opt/gitlab \
gitlab/gitlab-ce:10.2.4-ce.0
