# HyperCLOVAX-SEED 프로젝트

이 프로젝트는 HyperCLOVAX-SEED 모델을 사용하여 로컬 기기에서 대화형 AI를 실행하는 예제입니다.

## 모델 준비 방법

이 프로젝트에서는 `hyperclovax-seed-text-instruct-1.5b-q4_k_m.gguf` 모델을 사용합니다. 모델 파일을 준비하는 방법은 다음과 같습니다:

### 1. HuggingFace에서 다운로드

HuggingFace에서 직접 다운로드할 수 있습니다.

테스트용 모델의 HuggingFace 저장소 주소:
- https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf
- https://huggingface.co/cherryDavid/HyperCLOVAX-SEED-Text-Instruct-1.5B-Q4_K_M-GGUF
- https://huggingface.co/mradermacher/HyperCLOVAX-SEED-Text-Instruct-0.5B-GGUF
- https://huggingface.co/Qwen/Qwen3-0.6B-GGUF
- https://huggingface.co/Qwen/Qwen3-1.7B-GGUF

### 2. 프로젝트에 직접 포함하기

1. 위 링크에서 `hyperclovax-seed-text-instruct-1.5b-q4_k_m.gguf` 파일을 다운로드합니다.
2. 다운로드한 파일을 다음 경로에 복사합니다. `gemma3/model/hyperclovax-seed-text-instruct-1.5b-q4_k_m.gguf`


### 3. 모델 파일 위치 주의사항

모델 파일을 추가한 후 Xcode의 '빌드 설정'에서 다음을 확인하세요:
- Target > Build Phases > Copy Bundle Resources에 모델 파일이 포함되어 있는지 확인
- 모델 파일의 'Target Membership'이 제대로 설정되어 있는지 확인

## 코드 예제

이 프로젝트는 Template 구조체 문제로 인한 오류를 피하기 위해 template 없이 preprocess 함수를 직접 정의하는 방식을 사용합니다.

```swift
// 번들 모델을 사용하는 Bot 클래스
class LocalBot: LLM {
    convenience init() {
        // 모델 파일 경로
        let url = Bundle.main.url(forResource: "HyperCLOVAX-SEED-Text-Instruct-0.5B.f16", withExtension: "gguf")!
        
        // 시스템 프롬프트 정의
        let systemPrompt = "당신은 감정이 있는 AI입니다. 한국어로 대답하고, 100자 이내로 답변해주세요."
        
        // 기본 초기화
        self.init(from: url.path, stopSequence: "<end_of_turn>")!
        
        // 사용자 정의 preprocess 함수 설정
        self.preprocess = { input, history in
            var processed = ""
            processed += "시스템: \(systemPrompt)\n\n"
            for chat in history {
                if chat.role == .user {
                    processed += "<start_of_turn>user\n\(chat.content)<end_of_turn>\n"
                } else {
                    processed += "<start_of_turn>model\n\(chat.content)<end_of_turn>\n"
                }
            }
            processed += "<start_of_turn>user\n\(input)<end_of_turn>\n"
            processed += "<start_of_turn>model\n"
            return processed
        }
    }
}
```

## 참고사항

- 모바일 기기에서 실행할 때는 `maxTokenCount` 파라미터를 조정하여 성능을 최적화할 수 있습니다.
- 3B 이하 파라미터 모델을 모바일 기기에서 사용할 것을 권장합니다.
- 지원 플랫폼: macOS, iOS, watchOS, tvOS, visionOS
- LLM.swift 라이브러리의 Template 구조체 대신 preprocess 함수를 직접 정의하여 사용합니다.

## 프로젝트 구조

- `MainView.swift`: 메인 UI 및 모델 사용 예제 (현재 사용)
- `ContentView.swift`: 이전 UI 구현 (참조용)
- `gemma3App.swift`: 앱 진입점
- `model/`: 모델 파일이 포함된 디렉토리

## LLM.swift 라이브러리

이 프로젝트는 [LLM.swift](https://github.com/eastriverlee/LLM.swift/) 라이브러리를 사용합니다. 자세한 정보는 해당 저장소를 참조하세요. 
