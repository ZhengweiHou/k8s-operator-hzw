docker run \
-d \
-p 8443:443 \
-p 8090:80 \
--name gitlab \
-v ~/gitlabdata/etc:/etc/gitlab \
-v ~/gitlabdata/log:/var/log/gitlab \
-v ~/gitlabdata/data:/var/opt/gitlab \
gitlab/gitlab-ce
