#!/bin/bash

## 00 Set variables
source ./config.env

## check if ProxySQL is running
for PROXY_IP in "${PROXY_IPS[@]}"; 
    do
    PROXYSQL_STATUS=$(mysql -h $PROXY_IP -u$PROXY_USER -p$PROXY_PASSWORD -P $PROXY_PORT -e "SELECT 1;")
    if [ -z "${PROXYSQL_STATUS}" ]; then
        echo "ProxySQL status is not operationa. Exiting."
        exit
    fi
done

MEM_OKAY=1
while [ $MEM_OKAY -eq 1 ]
do
    # check memory on each pod
    for PXC_POD in "${PXC_PODS[@]}"; 
    do
        CONTAINER_MEM_USE=$(kubectl top pod -n $NAMESPACE $PXC_POD --containers | grep -v -E "log|MEMORY" | awk '{print $4}' | sed -e 's/Mi//g')      
        if [ $CONTAINER_MEM_USE -gt $MEMORY_BALANCING_LIMIT ] ; then
            for PROXY_IP in "${PROXY_IPS[@]}"; 
            do
                # dissalow connections to the pod that is about to be scaled vertically
                mysql -h $PROXY_IP -u$PROXY_USER -p$PROXY_PASSWORD -P $PROXY_PORT  -e \
        "UPDATE mysql_servers
SET status = \"OFFLINE_SOFT\", weight=10 
WHERE hostname <> \"${PXC_POD_HIGHEST_ORDINAL}.${STATEFULSET}.${NAMESPACE}.svc.cluster.local\";

LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;
        "
                kubectl patch statefulset $STATEFULSET -n $NAMESPACE -p "{\"spec\": {\"template\": {\"spec\":{\"containers\":[{\"name\":\"pxc\",\"resources\":{\"limits\":{\"memory\": \"${MEMORY_NEW_LIMIT}\"} }}]}}}}"

                MEM_OKAY=0
            done
        fi
        done         
done

declare -A POD_MEMORY
BALANCING=1
while [ $BALANCING -eq 1  ]
    do
    for PXC_POD in "${PXC_PODS[@]}"; 
    do
        if [ "$PXC_POD" == "$PXC_POD_HIGHEST_ORDINAL" ]; then
            continue
        else 
            # check memory usage of the remaing two pods
            CONTAINER_MEM_USE=$(kubectl top pod -n $NAMESPACE  $PXC_POD --containers | grep -v -E "log|MEMORY" | awk '{print $4}' | sed -e 's/Mi//g')
            POD_MEMORY["$PXC_POD"]=$MEMORY_MB

            LOWEST_MEMORY=0
            LOWEST_POD=""
            # get the pod with the highest memory usage
            for POD_NAME in "${!POD_MEMORY[@]}"; 
                do
                CURRENT_MEMORY=${POD_MEMORY["$POD_NAME"]}
                if (( $(echo "$CURRENT_MEMORY > $LOWEST_MEMORY" | bc -l) )); then
                    LOWEST_MEMORY=$CURRENT_MEMORY
                    LOWEST_POD=$POD_NAME
                fi
            done
            # direct the new workload to the pod with lower memory usage
            mysql -h $PROXY_IP -u$PROXY_USER -p$PROXY_PASSWORD -P 6032 -e \
            "UPDATE mysql_servers
SET status = \"ONLINE\", weight=1000
WHERE hostname = \"${LOWEST_POD}.${STATEFULSET}.${NAMESPACE}.svc.cluster.local\" ;
UPDATE mysql_servers
SET status = \"OFFLINE_SOFT\", weight=10 
WHERE hostname <>\"${LOWEST_POD}.${STATEFULSET}.${NAMESPACE}.svc.cluster.local\" ;

LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;
            "
        # check the status of the scaling pod
        SCALED_POD_STATUS=$(kubectl get pod "$PXC_POD_HIGHEST_ORDINAL" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$SCALED_POD_STATUS" == "True" ]; then
            # stop balancing once one of the pods has scaled
            BALANCING=0
            break
        fi
	fi
    done
done

# direct all new connections to the pod has scaled
mysql -h $PROXY_IP -u$PROXY_USER -p$PROXY_PASSWORD -P 6032 -e \
    "UPDATE mysql_servers
SET status = \"ONLINE\", weight=1000
WHERE hostname = \"${PXC_POD_HIGHEST_ORDINAL}.${STATEFULSET}.${NAMESPACE}.svc.cluster.local\" ;
UPDATE mysql_servers
SET status = \"OFFLINE_SOFT\", weight=10 
WHERE hostname <>\"${PXC_POD_HIGHEST_ORDINAL}.${STATEFULSET}.${NAMESPACE}.svc.cluster.local\" ;

LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;
            "

# forcefully close existing connections on the two pods that were used to balance the workload
for PXC_POD in "${PXC_PODS[@]}"; 
    do
        if [ "$PXC_POD" == "$PXC_POD_HIGHEST_ORDINAL" ]; then
            continue
        else
            kubectl exec -n $NAMESPACE "$PXC_POD" -c pxc -- mysql -h 127.0.0.1 -P $DB_PORT  -u $DB_USER -p$DB_PASSWORD mysql -s -e "CALL KillProcesses();" &>/dev/null
        fi
    done
   