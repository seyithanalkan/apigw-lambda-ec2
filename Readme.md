# apigw-lambda-ec2

This project, apigw-lambda-ec2, is designed to trigger a Lambda function through a POST request sent via API Gateway, which then creates an EC2 instance running Nginx.

## Prerequisites

Before you begin, ensure you have the following prerequisites installed and configured:

- **AWS Key and Secret Access Key:** Required for Terraform to interact with your AWS services. Obtain these from the IAM section in the AWS console.
- **Terraform:** This project uses Terraform to manage and provision AWS resources. Ensure it's installed on your machine.
- **An S3 Bucket for the Terraform Backend:** Necessary to store the Terraform state file, which keeps track of the resources Terraform creates.
- **Node.js and npm:** Required to install and run the Serverless Framework.
- **Serverless Framework:** Used to manage and deploy the AWS Lambda function. If it's not installed, the `deploy_script.sh` script will install it for you.

## Deployment

To deploy the project, execute the **`./deploy_script.sh create`** command. This script automates the entire deployment process, including the following steps:
#### Bash
```bash
git clone https://github.com/seyithanalkan/apigw-lambda-ec2.git
cd apigw-lambda-ec2
chmod +x deploy-script.sh
./deploy-script.sh create
```
1. **Terraform Creates Network:** The script initially switches the directory to **`terraform`.** It then **initializes, validates, plans, and applies** the Terraform configurations that define the network infrastructure to be created on AWS.
**The script saves the Terraform output to a `variables.json` file, which is later used to retrieve dynamic parameters for the Lambda function.**
2. **Serverless Deploys Lambda Function and API Gateway as Trigger:** If the Serverless Framework and the **`serverless-api-stage`** plugin aren't already installed, the script will install them. It then deploys the Serverless application, which sets up the Lambda function and the API Gateway that will trigger it.
#### Bash
```bash
sls  deploy  -s  dev
```
3. **CloudFormation Creates API Key:** The script substitutes **`<existing-api-gateway-id>`**  with the actual API Gateway ID in the  **`apikey-temp.yaml`** file using **`sed`**. It then deploys the stack using this file containing configurations to create an API key.

4. **Send POST Request with Curl Including API Key and JSON Body, Then Lambda Function Gets Dynamic Parameters:** After deploying the infrastructure, you can trigger the Lambda function by sending a POST request to the API Gateway. This request should include the API key in the header and a JSON body that contains the parameters for the EC2 instance to be created.
#### Bash
```bash
curl  -X POST -H "x-api-key: $api_key" -H "Content-Type: application/json" -d '{

"instance_type": "t2.2xlarge",

"subnet_id": "'$public_subnet_id'",

"security_group_id": "'$security_group_id'",

"key_pair_name": "MyAWSKey",

"ami_id": "'$AMI_ID'"

}' $api_url
```
5. **Lambda Creates EC2 Instance with Nginx Installed:** The Lambda function uses the parameters from the POST request to spin up an EC2 instance running Nginx. The function has the necessary permissions for creating and managing EC2 instances, as specified in the **`serverless.yml`** file.
6. **`deploy_script.sh`** **Returns Public IP of EC2:** Once the EC2 instance is up and running, the **`deploy_script.sh`** script outputs its public IP address. You can use this address to connect to the Nginx server running on the EC2 instance.
7. **Website Is Accessible from http://<public-ip>:** Finally, access the Nginx server by navigating to **`http://<public-ip>`** in your web browser.

## Uninstallation

To uninstall the project, execute the **`./deploy_script.sh remove`** command.

## Contributions

Contributions to this project are welcome! Whether it's reporting bugs, suggesting enhancements, or writing code, I appreciate your help. Please feel free to open an issue or submit a pull request on GitHub.

## Disclaimer

This project is designed for demonstrative purposes and is not recommended for use in production without further modifications. Specifically, it uses a **t2.2xlarge** EC2 instance, which **may result in AWS charges**. **Please be aware of this before running the deployment script.**