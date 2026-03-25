#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_ZIP="$SCRIPT_DIR/lambda_layer.zip"
DEPLOY_ZIP="$SCRIPT_DIR/lambda_deploy.zip"

echo "=== Build Lambda Deployment Package ==="
echo ""
echo "This builds a SINGLE deployment zip (code + dependencies)."
echo "No separate layer needed — simpler for small-scale use."
echo ""

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is required to compile native extensions for Amazon Linux."
    echo "       Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
fi

rm -rf "$SCRIPT_DIR/_lambda_build" "$DEPLOY_ZIP" "$OUTPUT_ZIP"
mkdir -p "$SCRIPT_DIR/_lambda_build"

# Copy the Lambda function code
if [ ! -f "$SCRIPT_DIR/lambda_function.py" ]; then
    echo "ERROR: lambda_function.py not found in $SCRIPT_DIR"
    echo "       Create it first (see DESIGN.md for the full code)."
    exit 1
fi
cp "$SCRIPT_DIR/lambda_function.py" "$SCRIPT_DIR/_lambda_build/"

echo "Choose your Lambda architecture:"
echo "  1) arm64  (default for new Lambda functions — cheaper)"
echo "  2) x86_64"
echo ""
read -r -p "Enter 1 or 2 [default: 1]: " ARCH_CHOICE
ARCH_CHOICE="${ARCH_CHOICE:-1}"

if [ "$ARCH_CHOICE" = "2" ]; then
    DOCKER_PLATFORM="linux/amd64"
    LAMBDA_ARCH="x86_64"
else
    DOCKER_PLATFORM="linux/arm64"
    LAMBDA_ARCH="arm64"
fi

echo ""
echo "Building for $LAMBDA_ARCH ($DOCKER_PLATFORM)..."
echo ""

docker run --rm \
    -v "$SCRIPT_DIR/_lambda_build":/build \
    --platform "$DOCKER_PLATFORM" \
    public.ecr.aws/sam/build-python3.12 \
    /bin/bash -c "
        pip install cryptography -t /build/ --quiet 2>&1 &&
        echo 'Dependencies installed'
    "

echo ""
echo "Creating deployment zip..."
cd "$SCRIPT_DIR/_lambda_build"
zip -r "$DEPLOY_ZIP" . -q

SIZE=$(du -h "$DEPLOY_ZIP" | cut -f1)
echo ""
echo "Output: $DEPLOY_ZIP ($SIZE)"
echo "Architecture: $LAMBDA_ARCH"

rm -rf "$SCRIPT_DIR/_lambda_build"

echo ""
echo "=== Deploy ==="
echo ""
echo "Upload directly as function code (no layer needed):"
echo ""
echo "  aws lambda update-function-code \\"
echo "    --function-name YOUR_FUNCTION_NAME \\"
echo "    --zip-file fileb://$DEPLOY_ZIP \\"
echo "    --architectures $LAMBDA_ARCH"
echo ""
echo "Make sure your function runtime is python3.12 and architecture is $LAMBDA_ARCH."
echo ""
echo "--- OR: Build as a layer instead ---"
echo ""

# Also build the layer zip (python/ prefix required)
LAYER_DIR="$SCRIPT_DIR/_layer_build"
rm -rf "$LAYER_DIR"
mkdir -p "$LAYER_DIR/python"

docker run --rm \
    -v "$LAYER_DIR/python":/out \
    --platform "$DOCKER_PLATFORM" \
    public.ecr.aws/sam/build-python3.12 \
    /bin/bash -c "
        pip install cryptography -t /out/ --quiet 2>&1 &&
        echo 'Layer packages installed'
    "

cd "$LAYER_DIR"
zip -r "$OUTPUT_ZIP" python/ -q

LAYER_SIZE=$(du -h "$OUTPUT_ZIP" | cut -f1)
rm -rf "$LAYER_DIR"

echo "Layer zip: $OUTPUT_ZIP ($LAYER_SIZE)"
echo ""
echo "  aws lambda publish-layer-version \\"
echo "    --layer-name cryptography-py312 \\"
echo "    --compatible-runtimes python3.12 \\"
echo "    --compatible-architectures $LAMBDA_ARCH \\"
echo "    --zip-file fileb://$OUTPUT_ZIP"
echo ""
echo "Then attach to your function:"
echo "  aws lambda update-function-configuration \\"
echo "    --function-name YOUR_FUNCTION_NAME \\"
echo "    --layers arn:aws:lambda:REGION:ACCOUNT:layer:cryptography-py312:VERSION"
