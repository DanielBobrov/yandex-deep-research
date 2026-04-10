import sys
lines = open('/root/yandex-deep-research/config.yaml').read().splitlines()
fixed = []
for line in lines:
    fixed.append(line)
    if 'Example: Novita AI (OpenAI-compatible)' in line:
        fixed.append('  - name: ya-deepseek-v3.2')
        fixed.append('    display_name: Yandex DeepSeek V3.2')
        fixed.append('    use: langchain_openai:ChatOpenAI')
        fixed.append('    model: gpt://b1gu96o8ga2ie9blre1f/deepseek-v32/latest')
        fixed.append('    api_key: $YANDEX_API_KEY')
        fixed.append('    base_url: https://ai.api.cloud.yandex.net/v1')
        fixed.append('    request_timeout: 600.0')
        fixed.append('    max_retries: 2')
        fixed.append('    max_tokens: 4096')
        fixed.append('    temperature: 0.7')
        fixed.append('    supports_thinking: false')
        fixed.append('    supports_vision: true')
        fixed.append('')

fixed.append('\nsandbox:\n  use: yandexdeepresearch.sandbox.local:LocalSandboxProvider\n')
open('/root/yandex-deep-research/config.yaml', 'w').write('\n'.join(fixed) + '\n')
