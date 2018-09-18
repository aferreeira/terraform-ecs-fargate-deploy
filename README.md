terraform-ecs-fargate-deploy
==================

<img alt="Terraform" src="https://cdn.rawgit.com/hashicorp/terraform-website/master/content/source/assets/images/logo-hashicorp.svg" width="600px">

It's a project created to deploy an ECS Cluster and create a service, tasks, codepipeline, codebuild, app up and down auto scaling with metrics and alerts in CloudWatch

## how to use
  - The name of your cluster and the whole infrastructure will be based on terraform.workspace your are using.
  - The first thing you'll have to do is set 2 variables on project and create your workspace based on you environment

## set vars

We have 2 variables to set, they are:

  - `region      = "us-east-1"`
  - `app-name    = "event-checker"`

Those variables are in this file:
```
.
├── terraform.tfvars
```

:shipit: `region`   = You can choose the AWS region to deploy your environment

:shipit: `app-name` = You need to set the repo name of your application

## set workspace for stage environment
```bash
$ terraform workspace new stage
$ terraform init
$ terraform apply
```

## set workspace for production environment
```bash
$ terraform workspace new production
$ terraform init
$ terraform apply
```

## post-deploy
 - After the whole deploy you can see your infrastructure created on amazon web console.

## validating application
 - When finish your **`terraform apply`** command, terraform will give you some outputs, you need to use **`alb_dns_name`** output as your URL to validade the REST API
 - This application also was created with swagger to facilitate access, just use http://<**`alb_dns_name`**>/swagger-ui.html on your web browser
