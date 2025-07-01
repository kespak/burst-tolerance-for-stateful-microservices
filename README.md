# burst-tolerance-for-stateful-microservices

## Introduction

This is prototype implementation of the method used to enhancing the burst tolerance of stateful microservices.

## The Method

Is a rule-based method that combines write-scaling and load balancing to distribute burst workloads across multiple stateful microservice nodes, while also vertically scaling a single node to meet rising demand. 

## Prerequisites

The following are the basics needed to use the balancing script:

1. A MySQL Galera Cluster statefulSet of three pods 
1. A ProxySQL statefulSet 
1. The stored procedure KillProcesses.sql applied to MySQL Galera Cluster, mysql database

## Configuration

kubectl must be configured to access the K8s environment
ProxySQL must be accessible
Config values set in config.env accordingly to the environment

## Running the scrip

The script will monitor the memory of Galera Cluster pods. Once memory on any of the pods reaches the threshold set in config.env file, it will initiate scaling of the statefulSet. The workload will then be balanced across the two remaining nodes. Until either the two nodes crash due to overwhelming load or until the 3rd pods scales vertically. Once the 3rd pod is scaled vertically, worload is transferred to it from the remaining two nodes.
