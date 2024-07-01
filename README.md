# DPTO-Automation

## About

This repository contains automation script to setting up environment for DPTO and distributed test execution in Ubuntu OS. Distributed tests will be executed within the Docker containers created using a custom Dockerfile for JMeter, data will be stored using Backend Listener in InfluxDB and monitoring can be done using Grafana. The environment will create the following items in the system:
1. a Docker network,
2. Docker containers, namely jmeter-master, influxdb and grafana,
3. JMeter slave containers, and
4. executed test results and dashboards.

The InfluxDB container has all basic configuration done for storing JMeter test data. The JMeter slave containers will be scaled according to test and tester's need and will be deleted immediately after test execution.

## Prerequisite

This automation is primarily based on Bash scripts; therefore, an Ubuntu or similar flavour OS is required. Additionally, Docker and JMeter are required to be installed in the same OS. Docker is used to create a common network, and JMeter, InfluxDB and Grafana containers. JMeter is used to design the required script for the distributed testing, where Backend Listener element is mandatory for maintaining a connection between the JMeter tests and InfluxDB database. Hence, the prerequisites are as follows:

1. An Ubuntu or similar OS
2. Docker
3. JMeter

## Repo Contents:

This repository contains or should contain the following files:

1. a Dockerfile for creating a custom JMeter Docker image,
2. the original jmeter.properties file,
3. the DPTO automation script,
4. a sample JMX script for reference, and
5. a JSON file for Grafana dashboard.

## Using Automation Script

There are 2 primary usage of the scripts- 1. to setup the DPTO environment, and 2. to execute the distributed tests. Here's how they can be done:

### Setting Up Environment

1. Clone the repository and open repo path in terminal.
2. Provide execute permission to the DPTO automation script, `chmod +x DPTO_script.sh`
3. Run the following command from the terminal, `./DPTO_script.sh INIT`

This will create all initial setup required for executing tests using DPTO. Once completed, follow the instructions printed in the terminal for setting up Grafana to monitor tests at the runtime and refer to the sample JMX script for creating your very own JMX scripts. Do remember to place your JMeter scripts in the same path as the DPTO automation script. Also replace the IP and DB in `influxdbUrl` value with the one printed in your terminal.

### Executing Tests

Just run the command `./DPTO_script.sh TEST <required no. of slave containers> <JMX script name>` and your test will be triggered successfully, while scaling the JMeter slave containers. For example, running the command `./DPTO_script.sh TEST 20 masterScript.jmx` will scale up 20 JMeter slave containers and run JMeter tests in all 20 containers using the masterScript.jmx script. Once the test is completed, the JMeter slave containers will be stopped and deleted from the system.

## Points Worth Noting

1. Before setting up environment or executing tests, check if the `docker.service` is in active state. If not, then start or restart it and then proceed. This will prevent unnecessary errors and warnings.
2. Remember to place your JMX script in the same directory as the DPTO automation script.
3. Change the IP and DB in `influxdbUrl` value with the one printed in your terminal.
4. Add data sources and import dashboard JSON file in the Grafana before you start executing tests. This will give you a real time monitoring of tests.
5. Setting up the DPTO environment is a one-time activity hence it is not to be executed multiple times.
6. The maximum number of slave containers that can be scaled up depends on memory and CPU cores configuration of your system and/or VM and the JMX script used.
7. The JSON file for Grafana is to be imported for creating JMeter Dashboard. The JSON file has all necessary configurations and can be edited based on your requirement. Additionally, you may use any other JSON file or create a custom dashboard of your own.

_Happy Testing!!!_
