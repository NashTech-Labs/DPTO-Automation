#!/bin/bash

# While executing this script, make sure to
# to keep the Dockerfile.jmeter, jmeter.properties,
# and JMX scripts at the same path.

# Constants and Variables
EPOCH=$(date +%s)
IP=$(hostname -I | awk '{print $1}')
SCRIPT_PATH="/jmeter/scripts"
DASHBOARD_PATH="$SCRIPT_PATH/dashboard_$EPOCH"
JMETER_HOME="/jmeter/apache-jmeter-5.6.3/bin"

# Function to print program usage
usage() {
  echo "Example:"
  echo "    $0 INIT"
  echo "or,"
  echo "    $0 TEST <no. of slave containers required for test execution> <JMX script name>"
  exit 1
}

# Function for initializing DPTO setup
init() {
  echo "#------ Creating a Docker network"
  docker network create --driver bridge jmeter-network

  echo "#------ Building the Dockerfile.jmeter image for Master-Slave Jmeter configuration"
  docker build -t jmeter-image -f Dockerfile.jmeter .

  echo "#------ Starting an InfluxDB container to store test data"
  docker run -d --name=influxdb --net=jmeter-network -p "$IP:8086:8086" -v influxdb-data:/var/lib/influxdb influxdb:1.8

  echo "#------ Waiting for InfluxDB to start in 5 seconds"
  sleep 5

  echo "#------ Creating JMeter DB, user and password for configuring the container"
  docker exec -it influxdb influx -execute "CREATE DATABASE jmeter_metrics"
  docker exec -it influxdb influx -execute "CREATE USER jmeter WITH PASSWORD 'password'"
  docker exec -it influxdb influx -execute "GRANT ALL ON jmeter_metrics TO jmeter"
  docker exec -it influxdb influx -execute "GRANT ALL PRIVILEGES TO jmeter"

  echo "#------ Starting InfluxDB service to apply configuration changes to the container"
  docker restart influxdb

  echo "#------ Starting a Grafana container for monitoring test data"
  docker run -d --name=grafana --net=jmeter-network -p "$IP:3000:3000" grafana/grafana

  echo "#------ Starting a JMeter Master container using the custom jmeter-image built earlier"
  docker run -it -d --name jmeter-master --network jmeter-network -v "$PWD":"$SCRIPT_PATH" jmeter-image

  sleep 5

  echo "#------ The JMeter Master, Grafana and InfluxDB containers are active"
  echo "#------ Open http://$IP:3000 in your browser"
  echo "#------ Login with user-password admin-admin (Skip new password process)"
  echo "#------ Click on 'Add your first data source' and select InfluxDB data source"
  echo "#------ Fill in HTTP Url as http://$IP:8086 and the InfluxDB Des with the following data:"
  echo "#------ o Database: jmeter_metrics"
  echo "#------ o User: jmeter"
  echo "#------ o Password: password"
  echo "#------ o HTTP Method: GET"
  echo "#------ Click on 'Save & test' to save the connection"
  echo "#------ Go to Grafana Home, click on 'Create your first dashboard' and then 'Add visualization' button"
  echo "#------ Select InfluxDB data source"
  echo "#------ In raw query mode, provide the following queries:"
  echo "#------ o 99th Percentile panel: SELECT percentile(\"pct99.0\", 99) FROM \"jmeter\" WHERE (\"application\"::tag = 'sauce_demo') AND \$timeFilter GROUP BY time(\$__interval) fill(0)"
  echo "#------ o HTTP Requests panel: SELECT count(\"hit\") FROM \"jmeter\" WHERE (\"application\"::tag = 'sauce_demo') AND \$timeFilter GROUP BY time(\$__interval) fill(0)"
  echo "#------ o Avg Response Time panel: SELECT max(\"avg\") FROM \"jmeter\" WHERE (\"application\"::tag = 'sauce_demo') AND \$timeFilter GROUP BY time(\$__interval) fill(0)"
  echo "#------ Remember to replace the application tag with your application name as used in the JMX script"
  echo "#------ This will help create the initial dashboard"
  echo "#------ This concludes the initial DPTO setup!!!"
  echo "#------ JMeter Script Configuration:"
  echo "#------ Open your sample jmx script and replace the IP in influxdbUrl value \"http://host_to_change:8086/write?db=jmeter\" with \"http://$IP:8086/write?db=jmeter_metrics\""
  echo "#------ To run a JMeter Distributed test, re-run the script with argument TEST"
  echo "#------ Program exiting successfully"
  exit 0
}

# Function to run a distributed test using arguments
run_test() {
  # Take user arguments for the number of slave containers needed
  SLAVE_COUNT=$1

  # Check if the input is greater than zero
  if [ "$SLAVE_COUNT" -le 0 ]; then
    echo "Invalid input. Please enter a valid positive integer greater than zero."
    exit 1
  fi

  # Take user argument for the JMX script to be executed for the distributed test
  JMX_SCRIPT=$2

  # Extract the file extension
  extension="${JMX_SCRIPT: -4}"

  # Check if the extracted extension is ".jmx"
  if [ "$extension" != ".jmx" ]; then
    echo "Invalid script name. Please enter a valid script name with .jmx extension."
    exit 1
  fi

  # Iterate through the provided argument to start the slave containers and run them in server mode
  for ((n=1; n<=SLAVE_COUNT; n++)); do
    docker run -dit --name jmeter-slave-$n --net jmeter-network -e REMOTE_HOSTS=jmeter-master -e REMOTE_HOSTNAME=jmeter-slave-$n jmeter-image
    docker exec -d jmeter-slave-$n nohup jmeter -s
    echo "#------ Container jmeter-slave-$n scaled up and started in server mode."
  done

  # Get the list of containers matching the pattern
  REMOTE_HOSTS=$(docker ps --format "{{.Names}}" | grep "jmeter-slave-" | paste -sd "," -)
  echo "List of REMOTE_HOSTS=$REMOTE_HOSTS"

  # Copy the original jmeter.properties file to a backup file
  docker exec -i jmeter-master cp "$JMETER_HOME/jmeter.properties" "$JMETER_HOME/jmeter.properties_orig_bkp"
  echo "#------ Backup of original jmeter.properties done successfully."

  # Replace the line in the jmeter.properties file
  docker exec -i jmeter-master sed -i "s|#remote_hosts=localhost:1099,localhost:2010|remote_hosts=$REMOTE_HOSTS|" "$JMETER_HOME/jmeter.properties"
  echo "#------ \"remote_hosts\" variable in jmeter.properties updated successfully."

  # Execute distributed test
  docker exec -d jmeter-master jmeter -n -t "$SCRIPT_PATH/$JMX_SCRIPT" -R "$REMOTE_HOSTS" -l "$DASHBOARD_PATH/results.jtl" -e -o "$DASHBOARD_PATH"
  echo "#------ Distributed Test has been triggered successfully. Check JMeter logs for more details."
  echo "====================================================================="

  # Tail the jmeter.log file in jmeter-master container
  docker exec -it jmeter-master bash -c '
	tail -f jmeter.log 2>/dev/null | grep --line-buffered "INFO o.a.j.JMeter: Dashboard generated" | while read -r line; do
	    if [[ "$line" =~ "INFO o.a.j.JMeter: Dashboard generated" ]]; then
		break
	    fi
	done
	echo "Test Completed! Continuing with the clean-up..."'

  # Restoring the original jmeter.properties file
  echo "====================================================================="
  docker exec -i jmeter-master cp "$JMETER_HOME/jmeter.properties_orig_bkp" "$JMETER_HOME/jmeter.properties"
  echo "#------ Original jmeter.properties restored successfully."

  # Stop and delete the Slave containers
  docker ps -a | grep "jmeter-slave" | awk '{print $1}' | xargs docker rm -f
  echo "#------ All slave containers scaled down successfully."
  echo "#------ Check Grafana dashboard for more test-related details."
  echo "#------ Program exiting successfully."
  exit 0
}

# Main
# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed or not accessible in the system, hence exiting."
  exit 1
fi

# Check script arguments
if [ "$#" -eq 0 ]; then
  usage
fi

# Process script arguments
case $1 in
  INIT)
    init
    ;;
  TEST)
    if [ -z "$2" ]; then
      echo "Error: Please provide the number of slave containers needed."
      usage
    fi
    if [ -z "$3" ]; then
      echo "Error: Please provide the JMX script name."
      usage
    fi
    if [ ! -f "$3" ]; then
      echo "Error: The JMX script \"$3\" does not exist in the current directory."
      usage
    fi
    run_test $2 $3
    ;;
  *)
    echo "Invalid argument, please use INIT as argument to initialize DPTO setup or TEST as argument to start a Dockerized Distributed Test"
    usage
    ;;
esac

