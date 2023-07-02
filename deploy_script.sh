#!/bin/bash

function create {
    # Change directory to terraform
    cd terraform

    # Initialize Terraform
    terraform init

    # Validate Terraform configuration
    terraform validate

    # Plan Terraform changes
    terraform plan

    # Apply Terraform changes with auto-approval
    terraform apply --auto-approve

    # Save Terraform output to variables.json file
    terraform output -json > variables.json

    # Display the content of variables.json file
    cat variables.json

    # Change back to the parent directory
    cd ..

    # Check if Serverless Framework is installed
    if ! command -v serverless &> /dev/null; then
        echo "Serverless Framework is not installed. Installing..."
        npm install -g serverless
    else
        echo "Serverless Framework is already installed."
    fi

    # Check if serverless-api-stage is installed
    if ! npm list -g --depth=0 | grep serverless-api-stage > /dev/null; then
        # If not installed, install it
        npm install --save-dev serverless-api-stage
    fi

    # Deploy the Serverless application with the 'dev' stage
    sls deploy -s dev

    # Get the AMI ID for Ubuntu image
    AMI_ID=$(aws ec2 describe-images --owners 099720109477 --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*' 'Name=virtualization-type,Values=hvm' --query 'Images[0].ImageId' --output text)
    echo "Latest Ubuntu AMI: $AMI_ID"

    # Get the API Gateway ID for the 'ec2-create-dev' API
    api_id=$(aws apigateway get-rest-apis --query 'items[?name==`ec2-create-dev`].id' --output text --region eu-central-1)
    echo "API Gateway ID: $api_id"

    # Construct the API URL using the API Gateway ID
    api_url="https://${api_id}.execute-api.eu-central-1.amazonaws.com/dev/create"
    echo "API URL: $api_url"

    # Replace <existing-api-gateway-id> with the actual API Gateway ID in apikey-temp.yaml
    sed "s|<existing-api-gateway-id>|$api_id|g" apikey.yaml > apikey-temp.yaml

    # Check if the CloudFormation stack exists
    if aws cloudformation describe-stacks --stack-name myapikey-stack >/dev/null 2>&1; then
        # Stack exists, check the stack status
        stack_status=$(aws cloudformation describe-stacks --stack-name myapikey-stack --query 'Stacks[0].StackStatus' --output text)
        if [ "$stack_status" = "CREATE_COMPLETE" ]; then
            # Stack is in CREATE_COMPLETE state, continue with the rest of the script
            echo "CloudFormation stack is already in CREATE_COMPLETE state. Continuing with the script..."
        elif [ "$stack_status" = "ROLLBACK_COMPLETE" ]; then
            # Stack is in ROLLBACK_COMPLETE state, delete the stack
            echo "Deleting CloudFormation stack in ROLLBACK_COMPLETE state..."
            aws cloudformation delete-stack --stack-name myapikey-stack
            # Wait for the stack to be deleted
            aws cloudformation wait stack-delete-complete --stack-name myapikey-stack
            # Create the stack
            echo "Creating CloudFormation stack..."
            aws cloudformation create-stack --template-body file://apikey-temp.yaml --stack-name myapikey-stack
            # Wait for the stack to be created
            aws cloudformation wait stack-create-complete --stack-name myapikey-stack
        elif [ "$stack_status" = "UPDATE_ROLLBACK_COMPLETE" ]; then
            # Stack is in UPDATE_ROLLBACK_COMPLETE state, delete the stack
            echo "Deleting CloudFormation stack in UPDATE_ROLLBACK_COMPLETE state..."
            aws cloudformation delete-stack --stack-name myapikey-stack
            # Wait for the stack to be deleted
            aws cloudformation wait stack-delete-complete --stack-name myapikey-stack
            # Create the stack
            echo "Creating CloudFormation stack..."
            aws cloudformation create-stack --template-body file://apikey-temp.yaml --stack-name myapikey-stack
            # Wait for the stack to be created
            aws cloudformation wait stack-create-complete --stack-name myapikey-stack
        else
            # Stack is in a different state, update the stack
            echo "Updating CloudFormation stack..."
            aws cloudformation update-stack --template-body file://apikey-temp.yaml --stack-name myapikey-stack
            # Wait for the stack update to complete
            aws cloudformation wait stack-update-complete --stack-name myapikey-stack
        fi
    else
        # Stack does not exist, create the stack
        echo "Creating CloudFormation stack..."
        aws cloudformation create-stack --template-body file://apikey-temp.yaml --stack-name myapikey-stack
        # Wait for the stack to be created
        aws cloudformation wait stack-create-complete --stack-name myapikey-stack
    fi


    # Remove the temporary apikey-temp.yaml file
    rm apikey-temp.yaml

    # Get the public subnet ID from variables.json using jq
    public_subnet_id=$(jq -r .public_subnet_id.value terraform/variables.json)
    echo "Public Subnet ID: $public_subnet_id"

    # Get the security group ID from variables.json using jq
    security_group_id=$(jq -r .security_group_id.value terraform/variables.json)
    echo "Security Group ID: $security_group_id"

    # Check if the API key already exists
    existing_api_key=$(aws apigateway get-api-keys --name-query "myapikey" --include-values --query 'items[0].id' --output text)

    if [ -z "$existing_api_key" ]; then
        echo "API Key is not found"
    else
        # API key already exists, retrieve the value
        api_key=$(aws apigateway get-api-key --api-key $existing_api_key --include-value --query 'value' --output text)
        echo "API Key already exists: $api_key"
    fi

    # Send a POST request to the API endpoint with the required parameters and API key
    curl_output=$(curl -X POST -H "x-api-key: $api_key" -H "Content-Type: application/json" -d '{
        "instance_type": "t2.xlarge",
        "subnet_id": "'$public_subnet_id'",
        "security_group_id": "'$security_group_id'",
        "key_pair_name": "MyAWSKey",
        "ami_id": "'$AMI_ID'"
    }' $api_url)

    echo "Curl Output: $curl_output"

    # Extract the instance ID from the curl output
    instance_id=$(echo $curl_output | jq -r '.instanceId')

    if [ "$instance_id" != "null" ]; then
        # Get the public IP address of the instance
        public_ip=$(aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        echo "Public IP of the instance: http://$public_ip"
    else
        echo "Failed to retrieve the public IP address of the instance."
    fi
}

function remove {
    #Terraform init before removing
    cd terraform
    terraform init
    cd ..

    # Terminate instances created by Lambda
    aws ec2 describe-instances --query 'Reservations[].Instances[?Tags[?Key==`CreatedBy` && Value==`Lambda`]].InstanceId' --output text | while read -r instance_id; do
        aws ec2 terminate-instances --instance-ids "$instance_id"
        echo "Terminated instance: $instance_id"
    done


    # Remove the Serverless application and destroy Terraform resources in parallel
    (sls remove && echo "Serverless application removed.") &
    (cd terraform && terraform destroy --auto-approve && echo "Terraform resources destroyed.") &

    # Wait for all background jobs to finish
    wait

    echo "Script completed."
}

case "$1" in
    create) create ;;
    remove) remove ;;
    *) echo "Usage: $0 {create|remove}" ;;
esac
