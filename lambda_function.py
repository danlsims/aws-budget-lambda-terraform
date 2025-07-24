import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    cloudfront = boto3.client('cloudfront')
    apigateway = boto3.client('apigateway')
    bedrock_agent = boto3.client('bedrock-agent')
    lambda_client = boto3.client('lambda')
    ecs = boto3.client('ecs')
    elbv2 = boto3.client('elbv2')
    
    try:
        # Get all running EC2 instances
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        instances_stopped = []
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                
                # Get CPU utilization for the instance
                cpu_response = cloudwatch.get_metric_statistics(
                    Namespace='AWS/EC2',
                    MetricName='CPUUtilization',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=context.aws_request_id,
                    EndTime=context.aws_request_id,
                    Period=300,
                    Statistics=['Average']
                )
                
                # Check if CPU utilization is at 100%
                if cpu_response['Datapoints']:
                    latest_cpu = cpu_response['Datapoints'][-1]['Average']
                    if latest_cpu >= 100:
                        # Stop the instance
                        ec2.stop_instances(InstanceIds=[instance_id])
                        instances_stopped.append(instance_id)
                        logger.info(f"Stopped instance {instance_id} due to 100% CPU utilization")
        
        # Pause CloudFront distributions
        cf_distributions = []
        cf_response = cloudfront.list_distributions()
        for dist in cf_response.get('DistributionList', {}).get('Items', []):
            if dist['Enabled']:
                dist_config = cloudfront.get_distribution_config(Id=dist['Id'])
                config = dist_config['DistributionConfig']
                config['Enabled'] = False
                cloudfront.update_distribution(
                    Id=dist['Id'],
                    DistributionConfig=config,
                    IfMatch=dist_config['ETag']
                )
                cf_distributions.append(dist['Id'])
                logger.info(f"Disabled CloudFront distribution {dist['Id']}")
        
        # Pause API Gateway endpoints
        api_endpoints = []
        apis_response = apigateway.get_rest_apis()
        for api in apis_response.get('items', []):
            stages_response = apigateway.get_stages(restApiId=api['id'])
            for stage in stages_response.get('item', []):
                apigateway.update_stage(
                    restApiId=api['id'],
                    stageName=stage['stageName'],
                    patchOps=[{
                        'op': 'replace',
                        'path': '/throttle/rateLimit',
                        'value': '0'
                    }]
                )
                api_endpoints.append(f"{api['id']}/{stage['stageName']}")
                logger.info(f"Throttled API Gateway {api['id']}/{stage['stageName']}")
        
        # Disable Bedrock agents
        bedrock_agents = []
        agents_response = bedrock_agent.list_agents()
        for agent in agents_response.get('agentSummaries', []):
            if agent['agentStatus'] == 'PREPARED':
                bedrock_agent.update_agent(
                    agentId=agent['agentId'],
                    agentName=agent['agentName'],
                    agentResourceRoleArn=agent.get('agentResourceRoleArn', ''),
                    foundationModel=agent.get('foundationModel', ''),
                    instruction=agent.get('instruction', ''),
                    agentStatus='NOT_PREPARED'
                )
                bedrock_agents.append(agent['agentId'])
                logger.info(f"Disabled Bedrock agent {agent['agentId']}")
        
        # Stop Lambda functions (except this one)
        lambda_functions = []
        functions_response = lambda_client.list_functions()
        for func in functions_response.get('Functions', []):
            if func['FunctionName'] != context.function_name:
                lambda_client.put_provisioned_concurrency_config(
                    FunctionName=func['FunctionName'],
                    ProvisionedConcurrencyConfig={'ProvisionedConcurrencySettings': {'ProvisionedConcurrency': 0}}
                )
                lambda_functions.append(func['FunctionName'])
                logger.info(f"Set concurrency to 0 for Lambda {func['FunctionName']}")
        
        # Stop ECS services
        ecs_services = []
        clusters_response = ecs.list_clusters()
        for cluster in clusters_response.get('clusterArns', []):
            services_response = ecs.list_services(cluster=cluster)
            for service in services_response.get('serviceArns', []):
                ecs.update_service(cluster=cluster, service=service, desiredCount=0)
                ecs_services.append(service.split('/')[-1])
                logger.info(f"Scaled down ECS service {service.split('/')[-1]}")
        
        # Stop Application Load Balancers
        albs_stopped = []
        albs_response = elbv2.describe_load_balancers()
        for alb in albs_response.get('LoadBalancers', []):
            if alb['State']['Code'] == 'active':
                elbv2.modify_load_balancer_attributes(
                    LoadBalancerArn=alb['LoadBalancerArn'],
                    Attributes=[{'Key': 'deletion_protection.enabled', 'Value': 'false'}]
                )
                elbv2.delete_load_balancer(LoadBalancerArn=alb['LoadBalancerArn'])
                albs_stopped.append(alb['LoadBalancerName'])
                logger.info(f"Deleted ALB {alb['LoadBalancerName']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed resource monitoring',
                'instances_stopped': instances_stopped,
                'cloudfront_disabled': cf_distributions,
                'api_endpoints_throttled': api_endpoints,
                'bedrock_agents_disabled': bedrock_agents,
                'lambda_functions_throttled': lambda_functions,
                'ecs_services_stopped': ecs_services,
                'albs_deleted': albs_stopped
            })
        }
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }