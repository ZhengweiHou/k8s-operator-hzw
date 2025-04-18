#!/bin/bash
# 如果不存在 /wiz/index/.runonce
runOnceFile=/wiz/storage/index/.runonce
mysqlUpgradeFile=/wiz/storage/index/.mysqlUpgrade


architecture=$(uname -m)
echo architecture = $architecture

isUbuntu=false

if [ "$architecture" = "armv7l" ]; then
  isUbuntu=true
  echo "current is arm, in ubuntu"
elif [ "$architecture" = "aarch64" ]; then
  isUbuntu=true
  echo "current is arm64, in ubuntu"
fi

mkdir -p /wiz/storage/logs/nginx
mkdir -p /wiz/storage/index
mkdir -p /wiz/storage/db


# mysql
echo "-----------------copy mysql config-----------------"
if [ "$isUbuntu" = true ]; then
  cp -fr /wiz/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
  cp /wiz/app/wizserver/libwizsqlcjk.so /usr/lib/mysql/plugin/
else
  cp -fr /wiz/config/my.cnf /etc
  cp /wiz/app/wizserver/libwizsqlcjk.so /usr/lib64/mysql/plugin/
fi
# nginx
echo "-----------------copy nginx config-----------------"
cp -fr /wiz/config/nginx.conf /etc/nginx
cp -fr /wiz/config/mime.types /etc/nginx
echo "-----------------copy crontab config-----------------"
cp -fr /wiz/config/crond /etc/pam.d 
if [ "$isUbuntu" = true ]; then
  cp -fr /wiz/config/root /var/spool/cron/crontabs
else
  cp -fr /wiz/config/root /var/spool/cron
fi
# executable
chmod u+x /wiz/app/clear_tmp.sh
chmod u+x /wiz/app/wait-for-it.sh
chmod u+x /wiz/app/template_upload.sh
chmod u+x /wiz/app/entrypoint.sh


if [ "$isUbuntu" = true ]; then
  echo "do nothing"
else
  chmod 644 /etc/my.cnf
fi
# 创建数据存储目录，这个在宿主机，只需要执行一次。
if [ ! -f "$runOnceFile" ]; then
  echo "----------init mysql database-------------"
   # mysql初始化数据库，在my.cnf里面指定了数据库位置
  if [ "$isUbuntu" = true ]; then
    mysqld --initialize-insecure --user=root --datadir=/wiz/storage/db
  else
    /usr/sbin/mysqld --initialize-insecure --user=root --datadir=/wiz/storage/db
  fi
fi

# 启动redis， nginx， mysql服务
echo "----------start redis-------------"
if [ "$isUbuntu" = true ]; then
  /usr/bin/redis-server &
else
  /usr/bin/redis-server /etc/redis.conf &
fi

echo "----------wait redis-------------"
/wiz/app/wait-for-it.sh -h 127.0.0.1 -p 6379 -t 60

echo "----------start nginx-------------"
/usr/sbin/nginx -c /etc/nginx/nginx.conf &

echo "----------start mysql-------------"
if [ "$isUbuntu" = true ]; then
  /etc/init.d/mysql start
else
  /usr/sbin/mysqld --user=root &
fi

echo "----------wait mysql-------------"
/wiz/app/wait-for-it.sh -h 127.0.0.1 -p 3306 -t 60
mysqlService=$?

# 修改mysql数据库密码，只需要执行一次
if [ ! -f "$runOnceFile" ]; then
  echo "----------change mysql password-------------"
  mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'aI9DCyNpEKWe9pn5';flush privileges"
fi

mysql -uroot -paI9DCyNpEKWe9pn5 -e "show databases;"
mysqlSock=$?

if [[ $mysqlService != 0 || $mysqlSock != 0 ]];then
  rm -f /var/lib/mysql/mysql.sock /var/lib/mysql/mysql.sock.lock /var/run/mysqld/mysqld.sock /var/run/mysqld/mysqld.sock.lock /var/run/mysqld/mysqld.pid
  if [[ $mysqlService != 0 ]];then
     rm -f /wiz/storage/db/ib_logfile0 /wiz/storage/db/ib_logfile1
  fi
  chmod  a+rwx  -R  /wiz/storage
  echo "------- The first start mysql faild ---------"
  echo "------- start mysql again  ---------"
  # 杀死之前的mysql进程
  ps aux |grep mysql|grep -v 'grep'|awk '{print $2}'|xargs kill
  if [ "$isUbuntu" = true ]; then
    /etc/init.d/mysql start
  else
    /usr/sbin/mysqld --user=root &
  fi
  /wiz/app/wait-for-it.sh -h 127.0.0.1 -p 3306 -t 60
  mysqlService=$?
  for i in {1..10}
  do
    mysql -uroot -paI9DCyNpEKWe9pn5 -e "show databases;"
    mysqlSock=$?
    if [[ $mysqlSock == 0 ]];then
      break;
    else
      sleep 10
    fi
  done
fi

if [[ $mysqlService != 0 || $mysqlSock != 0 ]];then
  echo "=====  start mysql failed ======"
  exit
fi

# 升级mysql
if [[ -f $runOnceFile && ! -f $mysqlUpgradeFile ]]; then
  mysql -uroot -paI9DCyNpEKWe9pn5 -e "show databases;"
  ## 针对wizbox老的docker服务修改mysql密码; 
  ## 老的wizbox密码是123456上条命令执行结果会失败，成功会返回0；
  if [[ $? != 0 ]]; then
    mysql_upgrade  -uroot -p123456
    mysql -uroot -p123456 -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'aI9DCyNpEKWe9pn5';flush privileges";
  else
    mysql_upgrade  -uroot -paI9DCyNpEKWe9pn5
  fi
  mysql -uroot -paI9DCyNpEKWe9pn5 -e "set @@global.show_compatibility_56=ON;"
  date > $mysqlUpgradeFile  
fi

echo "----------init and upgrade database-------------"
cd /wiz/app/wizserver
# 使用传入的外部数据库地址
if [[ -n $MYSQL_EXTERNAL_HOST && -n $MYSQL_EXTERNAL_USER && -n $MYSQL_EXTERNAL_PASSORD && -n $MYSQL_EXTERNAL_PORT ]];then
  NODE_ENV=production node  upgrade_db.js  -h $MYSQL_EXTERNAL_HOST -u $MYSQL_EXTERNAL_USER -p $MYSQL_EXTERNAL_PASSORD -P $MYSQL_EXTERNAL_PORT
else
  NODE_ENV=production node upgrade_db.js 
fi

if [[ ! -f "$runOnceFile"  && -n $ADMIN_PASSWORD ]]; then
  echo '----------init admin user password -------------'
  adminPassword=$(node init_user_password.js -p $ADMIN_PASSWORD)
  if [[ -n $MYSQL_EXTERNAL_HOST && -n $MYSQL_EXTERNAL_USER && -n $MYSQL_EXTERNAL_PASSORD && -n $MYSQL_EXTERNAL_PORT ]];then
    mysql -h$MYSQL_EXTERNAL_HOST -u$MYSQL_EXTERNAL_USER  -p$MYSQL_EXTERNAL_PASSORD -P$MYSQL_EXTERNAL_PORT -e "use wizasent; update wiz_user set password = '${adminPassword}' where email='admin@wiz.cn'"
  else
    mysql -uroot -paI9DCyNpEKWe9pn5 -e "use wizasent; update wiz_user set password = '${adminPassword}' where email='admin@wiz.cn'"
  fi
fi

echo "----------start node service-------------"
# 启动node服务
cd /wiz/app/wizserver/
pm2 start app.js --name="as" --log-date-format="YYYY-MM-DD HH:mm:ss.SSS" --max-memory-restart 1024M -f -- -s as
pm2 start app.js --name="note" --log-date-format="YYYY-MM-DD HH:mm:ss.SSS"  --max-memory-restart 3000M  -f -- -s note
pm2 start app.js --name="ws" --log-date-format="YYYY-MM-DD HH:mm:ss.SSS" --max-memory-restart 1024M -f -- -s ws
pm2 start app.js --name="index" --log-date-format="YYYY-MM-DD HH:mm:ss.SSS"  --node-args="--expose-gc" --max-memory-restart 3000M -f -- -c 1 -i 1 -t 1 -s index
pm2 start app.js --name="search" --log-date-format="YYYY-MM-DD HH:mm:ss.SSS" -f -- -s search
pm2 start app.js --name="editor" --log-date-format="YYYY-MM-DD HH:mm:ss.SSS" -f -- -s editor

# 初始化模版数据
if [ ! -f "$runOnceFile" ]; then
  echo "----------init template-------------"
  /wiz/app/wait-for-it.sh -h 127.0.0.1 -p 5001 -t 60
  asService=$?
  if [[ $asService != 0 ]]; then
    echo "as service start failed";
    exit;
  fi
  bash /wiz/app/template_upload.sh
  date  > $runOnceFile
fi

echo "----------start cron -------------"
if [ "$isUbuntu" = true ]; then
  cron -n
else
  crond -n
fi

tail -f /dev/null
