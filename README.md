# EFK-On-Docker
Step 1:
Install Docker and Docker Compose, by following the instructions in the below links
https://docs.docker.com/engine/install/ubuntu/
https://docs.docker.com/compose/install/

Step 2:
Unzip the opsmx.zip. Switch to opsmx folder

Step 3:
In docker-compose.yml, under fluentd:volumes, replace "/home/opsmx/logs" with your log folder
By default, elastic & kibana are bound to ports 9200 & 5601 respectively on the host. These ports should be open on the host for connecting to autopilot. If these are not available, you can change the same in the docker-compose.yml.
For example, to bind elasticsearch to port 9400 on the host,
ports:
- "9400:9200"

Step 4:
In opsmx folder, run
$docker-compose up -d
Check if elastic, kibana & fluentd containers are running
$docker ps
