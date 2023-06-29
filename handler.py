import json
import boto3

def create_instance(event, context):
    ec2 = boto3.resource('ec2')

    # event['body'] is a string, so we need to convert it to JSON
    body = json.loads(event['body'])

    instance_type = body['instance_type']
    subnet_id = body['subnet_id']
    security_group_id = body['security_group_id']
    key_pair_name = body['key_pair_name']
    ami_id = body['ami_id']

    user_data = """#!/bin/bash \n
    apt update -y &&
    apt install -y nginx &&
    echo "Hello World" > /var/www/html/index.html &&
    systemctl restart nginx"""

    # Create the instance with the specified subnet ID
    instances = ec2.create_instances(
        ImageId=ami_id,
        MinCount=1,
        MaxCount=1,
        InstanceType=instance_type,
        KeyName=key_pair_name,
        NetworkInterfaces=[
            {
                'DeviceIndex': 0,
                'SubnetId': subnet_id,
                'Groups': [security_group_id],
                'AssociatePublicIpAddress': True
            }
        ],
        UserData=user_data
    )

    # Wait for the instance to be running
    instances[0].wait_until_running()

    instance_id = instances[0].id

    return {
        "statusCode": 200,
        "body": json.dumps({
            "instanceId": instance_id,
        }),
    }
