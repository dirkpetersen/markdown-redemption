# Documentation Index

**The Markdown Redemption - AWS Lambda Deployment Documentation**

---

## Quick Start

For complete deployment guide, start with:
- **[FINAL.md](FINAL.md)** - Complete deployment guide with all steps
- **[FINAL.json](FINAL.json)** - Structured data with IAM policies

---

## Key Documents

### Deployment Guides
- **[FINAL.md](FINAL.md)** - Complete step-by-step deployment guide
- **[DEPLOYMENT_COMPLETE.md](DEPLOYMENT_COMPLETE.md)** - Initial deployment summary
- **[REBUILD_LAMBDA_PACKAGE.md](REBUILD_LAMBDA_PACKAGE.md)** - Build script instructions

### Configuration
- **[IAM_PERMISSIONS_GUIDE.md](IAM_PERMISSIONS_GUIDE.md)** - AWS IAM permissions required
- **[CUSTOM_DOMAIN_COMPLETE.md](CUSTOM_DOMAIN_COMPLETE.md)** - Custom domain setup
- **[DEPLOYMENT_AWS_INFRASTRUCTURE.md](DEPLOYMENT_AWS_INFRASTRUCTURE.md)** - Infrastructure overview

### Troubleshooting
- **[ERRORS.md](ERRORS.md)** - All 7 errors encountered and fixed
- **[KNOWN_ISSUES.md](KNOWN_ISSUES.md)** - Current limitations and workarounds
- **[CSS_INVESTIGATION.md](CSS_INVESTIGATION.md)** - CSS loading issue deep-dive

### Testing & Verification
- **[CURL_TEST_RESULTS.md](CURL_TEST_RESULTS.md)** - Complete curl test results
- **[DEPLOYMENT_VERIFIED.md](DEPLOYMENT_VERIFIED.md)** - Post-deployment validation

### Status Reports
- **[DEPLOYMENT_STATUS.md](DEPLOYMENT_STATUS.md)** - Current deployment state
- **[FINAL_STATUS.md](FINAL_STATUS.md)** - Final production status

---

## IAM Policy Files (JSON)

- **[FINAL.json](FINAL.json)** - Complete structured deployment data with all policies
- **[lambda-execution-role-policy.json](lambda-execution-role-policy.json)** - Lambda execution role
- **[sue-lambda-deployment-policy.json](sue-lambda-deployment-policy.json)** - Deployment user policy
- **[sue-lambda-trust-policy.json](sue-lambda-trust-policy.json)** - Lambda trust policy
- **[iam-dirk-updated-policy.json](iam-dirk-updated-policy.json)** - Updated IAM user policy

---

## Chronological Reading Order

For understanding the deployment journey:

1. **[DEPLOYMENT_AWS_INFRASTRUCTURE.md](DEPLOYMENT_AWS_INFRASTRUCTURE.md)** - Initial infrastructure plan
2. **[ERRORS.md](ERRORS.md)** - All errors encountered during deployment
3. **[CSS_INVESTIGATION.md](CSS_INVESTIGATION.md)** - CSS loading issue analysis
4. **[DEPLOYMENT_VERIFIED.md](DEPLOYMENT_VERIFIED.md)** - Verification results
5. **[CUSTOM_DOMAIN_COMPLETE.md](CUSTOM_DOMAIN_COMPLETE.md)** - Custom domain setup
6. **[FINAL.md](FINAL.md)** - Complete consolidated guide

---

## By Topic

### Binary Compatibility
- [ERRORS.md](ERRORS.md) - Error 1: GLIBC 2.27 issue
- [FINAL.md](FINAL.md) - Challenge 1: Binary compatibility solution

### Static Files & CSS
- [CSS_INVESTIGATION.md](CSS_INVESTIGATION.md) - Technical deep-dive
- [CSS_FIX_SUMMARY.md](CSS_FIX_SUMMARY.md) - Executive summary
- [ERRORS.md](ERRORS.md) - Error 5: CSS 404 issue
- [CURL_TEST_RESULTS.md](CURL_TEST_RESULTS.md) - CSS loading tests

### API Gateway
- [CUSTOM_DOMAIN_COMPLETE.md](CUSTOM_DOMAIN_COMPLETE.md) - Custom domain setup
- [ERRORS.md](ERRORS.md) - Error 6: API Gateway 403
- [ERRORS.md](ERRORS.md) - Error 7: Stage prefix in URLs

### IAM & Permissions
- [IAM_PERMISSIONS_GUIDE.md](IAM_PERMISSIONS_GUIDE.md) - Complete permission requirements
- [FINAL.json](FINAL.json) - Machine-readable policy definitions
- All `*-policy.json` files - Individual IAM policies

---

## File Count

- **Markdown files**: 19
- **JSON files**: 7
- **Total**: 26 documents

---

## Quick Reference

### Live URL
```
https://markdown.osu.internetchen.de/
```

### AWS Resources
- **Lambda**: markdown-redemption (Python 3.13)
- **API Gateway**: 43bmng09mi (REST API)
- **Custom Domain**: markdown.osu.internetchen.de
- **Certificate**: ACM d00a1b94-32ad-45ab-90b2-19d4b943e7b3
- **S3 Bucket**: markdown-redemption-usw2-1762126505

### Key Files to Reference
- Deployment: **FINAL.md** or **REBUILD_LAMBDA_PACKAGE.md**
- IAM Setup: **IAM_PERMISSIONS_GUIDE.md** or **FINAL.json**
- Troubleshooting: **ERRORS.md** or **KNOWN_ISSUES.md**
- Testing: **CURL_TEST_RESULTS.md**

---

**All documentation organized and ready for use.**
