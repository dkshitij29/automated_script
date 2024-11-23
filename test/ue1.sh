#!/bin/bash

# Define the ON and OFF durations in seconds
ON_DURATION=5
OFF_DURATION=5

# Define the iperf3 server details
SERVER_IP=172.16.0.1
SERVER_PORT=5006

while true; do
    echo "Generating traffic for ${ON_DURATION} seconds with varying rates..."
    
    # Loop through different rates
    for RATE in 1M 2M 3M 4M 5M 6M 7M 8M 9M 10M; do
        echo "Testing with ${RATE}..."
        sudo ip netns exec ue1 iperf3 -c ${SERVER_IP} -p ${SERVER_PORT} -i 1 -t 1 -b ${RATE}
    done

    echo "Pausing traffic for ${OFF_DURATION} seconds..."
    sleep ${OFF_DURATION}
done
