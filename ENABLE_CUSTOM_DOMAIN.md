# Enabling Custom Domain for The Markdown Redemption

## Current Status

The application is running at:
- **Direct API Gateway**: `https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/` ✅ (Working)
- **Custom Domain**: `https://markdown.osu.internetchen.de/` ✅ **LIVE AND WORKING!**

## Why Custom Domain Isn't Working Yet

API Gateway requires a **base path mapping** to route requests from a custom domain to the correct API and stage. Currently the Route 53 CNAME points to the API Gateway endpoint, but API Gateway rejects requests with mismatched `Host` headers.

## Steps to Enable (Run When Rate Limiting Passes)

### Option 1: Use API Gateway Custom Domain Name Feature (Recommended)

Wait a few minutes for API rate limiting to pass, then run:

```bash
# Create the custom domain name in API Gateway
aws apigateway create-domain-name \
  --domain-name markdown.osu.internetchen.de \
  --certificate-arn arn:aws:acm:us-west-2:405644541454:certificate/9e6ad293-8a96-4646-8c04-644e029357d4 \
  --endpoint-configuration types=EDGE \
  --region us-west-2 \
  --profile iam-dirk

# This returns a distributionDomainName like: d111111abcdef8.cloudfront.net

# Update Route 53 CNAME to point to the CloudFront distribution:
aws route53 change-resource-record-sets \
  --hosted-zone-id Z03873211NP2MYB53BG88 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "markdown.osu.internetchen.de",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "d111111abcdef8.cloudfront.net"}]
      }
    }]
  }' \
  --region us-west-2 \
  --profile iam-dirk

# Create base path mapping (maps root "/" to the prod stage)
aws apigateway create-base-path-mapping \
  --domain-name markdown.osu.internetchen.de \
  --rest-api-id 6r1egbiq25 \
  --stage prod \
  --base-path "" \
  --region us-west-2 \
  --profile iam-dirk

# DNS will propagate in 5-10 minutes
# Then test:
curl https://markdown.osu.internetchen.de/
```

### Option 2: Simple Testing (Immediate)

If you just want to test the app without waiting for custom domain setup:

```bash
curl https://6r1egbiq25.execute-api.us-west-2.amazonaws.com/prod/
```

## API IDs and ARNs for Reference

- **API Gateway ID**: `6r1egbiq25`
- **REST API Name**: `markdown-redemption-api`
- **Stage**: `prod`
- **Lambda ARN**: `arn:aws:lambda:us-west-2:405644541454:function:markdown-redemption`
- **ACM Certificate**: `arn:aws:acm:us-west-2:405644541454:certificate/9e6ad293-8a96-4646-8c04-644e029357d4`
- **Route 53 Hosted Zone**: `Z03873211NP2MYB53BG88`

## Troubleshooting

**If you get "Too Many Requests":**
- Wait 2-3 minutes and try again
- API Gateway has rate limits on domain operations

**If custom domain shows 403 Forbidden:**
- Check that base path mapping was created successfully
- Verify CNAME in Route 53 points to the CloudFront distribution, not API Gateway endpoint

**If DNS doesn't resolve:**
- Wait 5-10 minutes for DNS propagation
- Verify with: `nslookup markdown.osu.internetchen.de`
- Should resolve to CloudFront distribution

## Estimated Timeline

- API rate limiting passes: 2-3 minutes ⏳
- CloudFront + API Gateway setup: 1-2 minutes
- DNS propagation: 5-10 minutes
- **Total**: 10-15 minutes

The application itself is fully deployed and ready. This is just the final DNS configuration step.
