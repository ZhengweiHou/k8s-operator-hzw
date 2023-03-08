docker run -itd --name db2 --privileged=true -p 50000:50000 -e LICENSE=accept -e DB2INST1_PASSWORD=admin -e DBNAME=testdb  -v /home/houzw/rundata/DATA_db2/database1:/database ibmcom/db2:11.5.8.0

