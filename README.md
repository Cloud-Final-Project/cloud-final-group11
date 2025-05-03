# cloud-final-group11
This repo will be used to hold the infrastructure code for the ENPM818N final project

Current folder structure:

aws-otel-project/
├── terraform/
│   ├── modules/                    ← reusable Terraform modules
│   │   ├── vpc/
│   │   │   └── {main,variables,outputs}.tf
│   │   ├── eks-cluster/
│   │   │   └── {main,variables,outputs}.tf
│   │   └── iam/
│   │       └── {main,variables,outputs}.tf
│   ├── phase1-eks/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── phase2-helm/
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── phase3-alerting/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── phase4-ci-cd/                ← if you choose to Terraform CodeBuild/CodePipeline
│       ├── main.tf
│       └── variables.tf
├── k8s/
│   ├── manifests/
│   │   └── opentelemetry-demo.yaml  ← original or modified
│   └── helm-values/
│       └── values.yaml
├── .github/
│   └── workflows/
│       └── ci-cd-pipeline.yml       ← GitHub Actions
├── docs/
│   └── final-report.md
└── video/
    └── demo.mp4

Currently docs and video folders are not required
