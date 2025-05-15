import SwiftUI
import LLM

// 번들 모델을 사용하는 Bot 클래스
class LocalBot: LLM {
    // 모델 파일 경로를 저장
    private static var cachedModelPath: String?
    
    // 전체 대화 내용을 별도로 관리
    private var conversations: [(question: String, answer: String)] = []
    
    // 대화 내용 표시용 변수
    @Published var currentQuestion: String = ""
    @Published var isGenerating: Bool = false
    @Published var generatedText: String = ""
    
    // 응답 생성 제한 설정
    private let maxResponseLength = 200 // 최대 응답 길이 (문자 수)
    private let responseTimeout = 5.0 // 응답 생성 타임아웃 (초)
    
    // KV 캐시 상태 추적 변수
    @Published var kvCacheInfo: String = "KV 캐시 정보 없음"
    @Published var tokenCountInfo: String = "토큰 정보 없음"
    
    // 컨텍스트 크기 저장용 변수 (정적으로 선언)
    //static let DEFAULT_CONTEXT_SIZE: Int32 = 256
    static let DEFAULT_CONTEXT_SIZE: Int32 = 512
    
    // 응답 생성 상태 추적 변수 추가
    private var isResponseCompleted: Bool = true
    
    // 완전 초기화 여부 플래그 추가
    private var isFullyInitialized: Bool = false
    
    convenience init() {
        print("=== 🚀 LocalBot 초기화 시작 ===")
        // 모델 파일 경로를 여러 방식으로 시도
        var modelUrl: URL? = nil
        
        // 1. 기본 경로 시도
        modelUrl = Bundle.main.url(forResource: "hyperclovax-seed-text-instruct-1.5b-q4_k_m", withExtension: "gguf")
        if modelUrl != nil {
            print("✅ 모델 파일 찾음: 기본 경로")
        }
        
        // 모델 파일을 찾지 못하면 오류 로그 출력
        guard let finalModelUrl = modelUrl else {
            print("❌ 모델 파일을 찾을 수 없습니다. 번들에 모델 파일이 포함되어 있는지 확인하세요.")
            print("💡 모델 다운로드 방법: README.md 파일을 참조하세요.")
            // 임시로 빈 경로 설정 (앱이 충돌하지 않도록)
            self.init(from: "")!
            return
        }
        
        // 모델 경로 캐싱
        LocalBot.cachedModelPath = finalModelUrl.path
        print("🔍 사용할 모델 경로: \(finalModelUrl.path)")
        
        // 시스템 프롬프트 정의 - 더 짧게 수정
        let systemPrompt = """
        당신은 한국어로 응답하는 AI 어시스턴트입니다.
        간결하게 답변해주세요.
        사용자의 질문에 한 번만 답변하고 멈추세요.
        """
        print("💬 시스템 프롬프트 설정: \(systemPrompt)")
        
        // KV 캐시 충돌 방지를 위해 historyLimit을 0으로 설정
        print("🔄 모델 초기화 중... (시간이 걸릴 수 있습니다)")
        
        // maxTokenCount를 줄여서 KV 캐시 부족 방지
        let contextSize = LocalBot.DEFAULT_CONTEXT_SIZE
        self.init(from: finalModelUrl.path, stopSequence: "<end_of_turn>", historyLimit: 0, maxTokenCount: contextSize)!
        
        // 템플릿 명시적 설정
        self.template = Template(
            user: ("User: ", "\n"),
            bot: ("Assistant: ", "\n"),
            stopSequence: "User:",
            systemPrompt: systemPrompt
        )
        
        // 초기화 완료 표시
        self.isFullyInitialized = true
        
        print("✅ 모델 초기화 완료")
        print("📚 히스토리 제한: 최대 \(self.historyLimit)개 대화")
        print("🔢 최대 토큰 수: \(contextSize) (입력과 출력을 포함한 전체 컨텍스트 크기)")
        print("=== 🎉 LocalBot 초기화 완료 ===")
    }
    
    // 대화 기록 초기화 함수 추가
    func clearHistory() {
        print("🧹 대화 기록 초기화 중...")
        // LLM 내부 history 배열 초기화
        self.history.removeAll()
        // 로컬 conversations 배열 초기화
        conversations.removeAll()
        
        // 응답 생성 상태 초기화
        isResponseCompleted = true
        
        // UI 상태 초기화
        currentQuestion = ""
        generatedText = ""
        isGenerating = false
        
        print("✅ 대화 기록 초기화 완료")
    }
    
    // 완전한 초기화 (모델 상태 포함)
    func fullReset() async {
        print("🔄 모델 전체 상태 초기화 중...")
        
        // 진행 중인 생성 중단
        self.stop()
        
        // 기존 상태 모두 초기화
        clearHistory()
        
        // 메모리 정리 요청
        #if os(iOS) || os(macOS)
        if #available(iOS 15.0, macOS 12.0, *) {
            print("🧹 메모리 정리 요청")
            // 메모리 정리 간접 유도 (직접적인 API는 없음)
            Task {
                // 일시적으로 큰 객체 할당 후 해제하여 GC 유도
                autoreleasepool {
                    let _ = [UInt8](repeating: 0, count: 1024 * 1024)
                }
                
                // 짧은 지연으로 메모리 정리 시간 제공
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1초
            }
        }
        #endif
        
        // LLM 내부 캐시 정리 시도 (강제 GC)
        await Task.yield()
        
        print("✅ 모델 전체 상태 초기화 완료")
    }
    
    // KV 캐시 상태 출력 함수 추가
    func checkKVCacheStatus() async -> String {
        // 실제로는 llama.cpp에 직접 접근 필요하지만 Swift에서는 제한적
        // C API가 노출되어 있지 않으므로 간접적인 정보 수집
        let tokenInfo = await estimateTokenUsage()
        
        return "컨텍스트 최대 크기: \(LocalBot.DEFAULT_CONTEXT_SIZE) 토큰 | 현재 사용량 추정: \(tokenInfo)"
    }
    
    // 현재 토큰 사용량 추정 함수
    func estimateTokenUsage() async -> String {
        var totalTokens = 0
        
        // 시스템 프롬프트 토큰 추정 (대략 50 토큰)
        let systemPromptTokens = 50
        
        // 현재 대화 기록의 토큰 추정
        for conversation in conversations {
            // 영어 기준으로 대략 단어당 1.3 토큰, 한글은 문자당 약 0.4 토큰으로 추정
            let questionTokens = Int(Double(conversation.question.count) * 0.4)
            let answerTokens = Int(Double(conversation.answer.count) * 0.4)
            
            // 템플릿 토큰 추가 (약 20 토큰)
            totalTokens += questionTokens + answerTokens + 20
        }
        
        // 현재 생성 중인 텍스트의 토큰 추정
        let currentGenerationTokens = Int(Double(generatedText.count) * 0.4)
        
        // 현재 질문의 토큰 추정
        let currentQuestionTokens = Int(Double(currentQuestion.count) * 0.4)
        
        // 총 토큰 수 (시스템 프롬프트 + 대화 기록 + 현재 대화)
        totalTokens += systemPromptTokens + currentQuestionTokens + currentGenerationTokens
        
        return "\(totalTokens) 토큰 (추정치)"
    }
    
    // 커스텀 응답 처리 메서드
    func customRespond(to input: String) async -> String {
        print("🔄 대화 처리 시작: \(input)")
        
        // 이전 응답이 완료되지 않았다면 초기화
        if !isResponseCompleted {
            print("⚠️ 이전 응답이 완료되지 않았습니다. 상태를 초기화합니다.")
            await fullReset()
        }
        
        // 응답 생성 시작 전 상태 설정
        isResponseCompleted = false
        
        // 응답 생성 전 history 초기화 - 각 질문을 독립적으로 처리
        clearHistory()
        
        // KV 캐시 상태 확인 및 업데이트
        let cacheStatus = await checkKVCacheStatus()
        await MainActor.run {
            kvCacheInfo = cacheStatus
            tokenCountInfo = "입력: \(Int(Double(input.count) * 0.4)) 토큰 (추정)"
        }
        
        // UI 업데이트를 위한 상태 설정
        await MainActor.run {
            currentQuestion = input
            isGenerating = true
            generatedText = ""
        }
        
        // LLM의 기본 요청-응답 동작 설정
        var responseText = ""
        
        // 타임아웃 처리를 위한 시작 시간 기록
        let startTime = Date()
        
        // 타임아웃 작업 생성
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(responseTimeout * 1_000_000_000))
                if !isResponseCompleted {
                    print("⏱️ 응답 생성 타임아웃: \(responseTimeout)초 경과")
                    // 타임아웃 발생 시 응답 생성 중단
                    self.stop()
                    
                    // 타임아웃 발생 시 강제 종료 처리
                    await MainActor.run {
                        if generatedText.isEmpty {
                            generatedText = "응답을 생성할 수 없습니다. 다시 시도해주세요."
                        }
                        isGenerating = false
                    }
                    // 응답 생성 완료 표시
                    isResponseCompleted = true
                }
            } catch {
                print("⚠️ 타임아웃 처리 중 오류: \(error)")
            }
        }
        
        // 업데이트 핸들러 설정
        let originalUpdateHandler = self.update
        self.update = { outputDelta in
            // 현재 시간 확인하여 최대 길이 초과 처리
            if responseText.count > self.maxResponseLength {
                if !self.isResponseCompleted {
                    print("⚠️ 응답 생성 제한에 도달: 최대 길이 초과")
                    self.stop()
                    self.isResponseCompleted = true
                    
                    Task { @MainActor in
                        self.isGenerating = false
                        self.generatedText = responseText
                    }
                    
                    // 타임아웃 작업 취소
                    timeoutTask.cancel()
                }
                return
            }
            
            if let delta = outputDelta {
                responseText += delta
                
                // stopSequence 확인
                if responseText.contains("<end_of_turn>") && !self.isResponseCompleted {
                    print("✅ stopSequence 감지됨")
                    self.isResponseCompleted = true
                    
                    Task { @MainActor in
                        self.isGenerating = false
                        self.generatedText = responseText
                    }
                    
                    // 타임아웃 작업 취소
                    timeoutTask.cancel()
                    return
                }
                
                Task { @MainActor in
                    self.generatedText = responseText
                }
            } else {
                // outputDelta가 nil이면 응답 생성이 완료된 것
                if !self.isResponseCompleted {
                    self.isResponseCompleted = true
                    
                    // 응답이 비어있지 않고 stopSequence로 끝나지 않으면 추가
                    if !responseText.isEmpty && !responseText.hasSuffix("<end_of_turn>") {
                        responseText += " <end_of_turn>"
                    }
                    
                    Task { @MainActor in
                        self.isGenerating = false
                        self.generatedText = responseText
                    }
                    
                    // 타임아웃 작업 취소
                    timeoutTask.cancel()
                }
                
                print("✅ 응답 생성 완료 (stopSequence 도달 또는 생성 종료)")
            }
        }
        
        // LLM 기본 메소드 호출
        do {
            // 응답 생성 시작
            await Task {
                await self.respond(to: input)
            }.value
            
            // 응답 생성이 완료된 후 타임아웃 작업 취소
            timeoutTask.cancel()
        } catch {
            // 오류 발생 시 타임아웃 작업 취소
            timeoutTask.cancel()
            
            print("🆘 응답 생성 중 오류 발생: \(error)")
            responseText = "응답을 생성하는 중 오류가 발생했습니다. 다시 시도해주세요."
            isResponseCompleted = true
            
            await MainActor.run {
                isGenerating = false
                generatedText = responseText
            }
        }
        
        // 원래 핸들러 복원
        self.update = originalUpdateHandler
        
        // 최종 응답 가져오기
        if responseText.isEmpty {
            responseText = "응답을 생성할 수 없습니다."
        }
        
        // 응답 생성이 아직 완료되지 않았다면 강제로 완료 상태로 설정
        if !isResponseCompleted {
            self.stop()
            isResponseCompleted = true
            await MainActor.run {
                isGenerating = false
            }
        }
        
        // <end_of_turn> 토큰 제거하여 사용자에게 보여주는 응답 정리
        let cleanedResponse = responseText.replacingOccurrences(of: "<end_of_turn>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 응답 생성 후 KV 캐시 상태 업데이트
        let finalCacheStatus = await checkKVCacheStatus()
        await MainActor.run {
            kvCacheInfo = finalCacheStatus
            tokenCountInfo = "입력: \(Int(Double(input.count) * 0.4)) 토큰, 출력: \(Int(Double(cleanedResponse.count) * 0.4)) 토큰 (추정)"
        }
        
        print("✅ 응답 생성 완료: \(cleanedResponse.prefix(30))...")
        
        // 대화 기록에 추가
        conversations.append((question: input, answer: cleanedResponse))
        print("📚 대화 기록 업데이트: 총 \(conversations.count)개 대화")
        
        // 응답 완료 후 메모리/상태 정리 (중요)
        clearHistory()
        
        // 응답 반환
        return cleanedResponse
    }
    
    // 히스토리 상태 출력 함수
    func printConversations() {
        print("📚 현재 대화 기록 (총 \(conversations.count)개):")
        for (index, conv) in conversations.enumerated() {
            print("  \(index+1). 질문: \(conv.question.prefix(30))...")
            print("     답변: \(conv.answer.prefix(30))...")
        }
        
        print("📚 LLM 내부 대화 기록 (총 \(history.count)개):")
        for (index, chat) in history.enumerated() {
            print("  \(index+1). 역할: \(chat.role == .user ? "사용자" : "봇")")
            print("     내용: \(chat.content.prefix(30))...")
        }
    }
}

// 간단한 인디케이터 뷰 (정적으로 항상 표시)
struct SimpleLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                
                Text("응답 생성 중...")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            .padding(16)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(16)
        }
        .frame(maxWidth: .infinity)
    }
}

// 채팅 인터페이스 뷰
struct ChatView: View {
    @State private var bot = LocalBot()
    @State var input = "“계속 같은 문제가 발생하는데, context7을 사용해서 해결방법을 찾아봐” 이 문장의 핵심 키워드 3개를 찾아줘"
    @State private var previousInput = "" // 이전 입력 저장용
    @State private var chatHistory: [(question: String, answer: String)] = []
    @State private var isInputDisabled = false
    @State private var isResetting = false
    
    // 로딩 상태를 명시적으로 관리하는 변수 추가
    @State private var isLoading = false
    
    init() { 
        print("📱 ChatView 초기화")
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // 상단 타이틀 바 및 초기화 버튼 추가
            HStack {
                Text("HyperCLOVAX-SEED 대화")
                    .font(.headline)
                    .padding(.horizontal)
                
                Spacer()
                
                Button(action: resetChat) {
                    Label("초기화", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .disabled(isInputDisabled || isResetting)
                .overlay(
                    isResetting ?
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.7)
                    : nil
                )
            }
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            // KV 캐시 정보 표시
            HStack {
                Text("🧠 \(bot.kvCacheInfo)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal)
            
            // 토큰 정보 표시
            HStack {
                Text("🔢 \(bot.tokenCountInfo)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal)
            
            // 로딩 인디케이터를 상단에 배치 (항상 표시 영역)
            if isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                        .scaleEffect(1.5)
                    
                    Text("응답 생성 중...")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // 채팅 히스토리 표시
            ScrollView { 
                VStack(alignment: .leading, spacing: 16) {
                    // 모든 대화 표시
                    ForEach(0..<chatHistory.count, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("질문: \(chatHistory[i].question)")
                                .padding(10)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("답변: \(chatHistory[i].answer)")
                                .padding(10)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // 현재 진행 중인 대화 표시
                    if !bot.currentQuestion.isEmpty {
                        Text("질문: \(bot.currentQuestion)")
                            .padding(10)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 응답 표시
                        if !bot.generatedText.isEmpty {
                            Text(bot.generatedText.replacingOccurrences(of: "<end_of_turn>", with: ""))
                                .padding(10)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // 입력 영역
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).foregroundStyle(.thinMaterial).frame(height: 40)
                    TextField("입력하세요", text: $input)
                        .padding(8)
                        .onSubmit {
                            respond() // Enter 키 입력 시 응답 생성
                        }
                        .disabled(isInputDisabled || isResetting) // 응답 생성 또는 초기화 중에는 입력 비활성화
                }
                Button(action: respond) { 
                    Image(systemName: "paperplane.fill") 
                }
                .disabled(isInputDisabled || isResetting) // 응답 생성 또는 초기화 중에는 버튼 비활성화
                
                Button(action: stop) { 
                    Image(systemName: "xmark") 
                }
                .disabled(!isLoading || isResetting) // 응답 생성 중에만 활성화
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .onAppear {
            print("📱 ChatView가 화면에 나타남")
            Task {
                let cacheStatus = await bot.checkKVCacheStatus()
                print("🧠 초기 KV 캐시 상태: \(cacheStatus)")
            }
        }
    }
    
    // Bot만 초기화하고 chatHistory는 유지하는 함수
    func resetBotOnly() {
        print("🔄 Bot만 초기화 (chatHistory는 유지)")
        isInputDisabled = true
        isResetting = true
        // isLoading 설정 제거 (로딩 인디케이터 유지)
        Task {
            await bot.fullReset()
            await MainActor.run {
                bot = LocalBot()
                isInputDisabled = false
                isResetting = false
            }
            
            // KV 캐시 상태 업데이트 추가
            let cacheStatus = await bot.checkKVCacheStatus()
            await MainActor.run {
                bot.kvCacheInfo = cacheStatus
                bot.tokenCountInfo = "초기화 후 토큰 정보 (새 세션 시작)"
            }
            
            await Task.yield()
            print("✅ Bot만 초기화 완료 (chatHistory 유지)")
        }
    }
    
    func respond() { 
        guard !input.isEmpty else { return }
        
        print("💬 사용자 입력: \(input)")
        previousInput = input // 현재 입력 저장
        
        // 입력 필드 비우기
        input = ""
        // 응답 생성 중에는 입력 비활성화
        isInputDisabled = true
        
        // 로딩 상태를 true로 설정 - 응답 생성 시작
        isLoading = true
        print("🚨 로딩 상태 ON: \(isLoading)")
        
        // Bot만 초기화 (chatHistory는 유지)
        resetBotOnly()
        
        // resetBotOnly 호출 후 다시 로딩 상태 설정 (로딩 인디케이터 유지)
        isLoading = true
        
        Task { 
            print("🤖 응답 생성 시작")
            
            // 초기 KV 캐시 상태 업데이트 (입력 전)
            let initialCacheStatus = await bot.checkKVCacheStatus()
            await MainActor.run {
                bot.kvCacheInfo = initialCacheStatus
                bot.tokenCountInfo = "입력: \(Int(Double(previousInput.count) * 0.4)) 토큰 (추정)"
            }
            
            // chatHistory와 previousInput을 결합하여 컨텍스트 생성
            var combinedInput = ""
            
            // 이전 대화 내용을 포함 (대화가 길어지면 너무 느려짐. 그리고 제대로 기억 못함)
            /*if !chatHistory.isEmpty {
                for chat in chatHistory {
                    combinedInput += "질문: \(chat.question)\n"
                    combinedInput += "답변: \(chat.answer)\n\n"
                }
                combinedInput += "이전 대화를 바탕으로 다음 질문에 답변해주세요.\n\n"
            }*/
            
            // 현재 질문 추가
            combinedInput += previousInput
            
            print("📚 전체 컨텍스트와 함께 질문 요청: \(combinedInput.prefix(100))...")
            
            // 커스텀 응답 처리 메서드 사용 (chatHistory + previousInput 전달)
            let answer = await bot.customRespond(to: combinedInput)
            
            // 응답 생성 후 KV 캐시 상태 업데이트
            let finalCacheStatus = await bot.checkKVCacheStatus()
            await MainActor.run {
                bot.kvCacheInfo = finalCacheStatus
                bot.tokenCountInfo = "입력: \(Int(Double(previousInput.count) * 0.4)) 토큰, 출력: \(Int(Double(answer.count) * 0.4)) 토큰 (추정)"
            }
            
            // UI 업데이트
            await MainActor.run {
                chatHistory.append((question: previousInput, answer: answer))
                // 응답 완료 후 입력 활성화
                isInputDisabled = false
                
                // 로딩 상태를 false로 설정 - 응답 생성 완료
                isLoading = false
                print("🚨 로딩 상태 OFF: \(isLoading)")
            }
            
            print("✅ 응답 생성 완료")
            
            // 모든 대화 기록 출력
            bot.printConversations()
        } 
    }
    
    func stop() { 
        print("🛑 응답 생성 중단")
        bot.stop()
        // 응답 중단 후 입력 활성화
        isInputDisabled = false
        
        // 로딩 상태를 false로 설정 - 응답 생성 중단
        isLoading = false
        print("🚨 로딩 상태 OFF(중단): \(isLoading)")
    }
    
    func resetChat() {
        print("🧹 대화 완전 초기화 시작")
        
        // 초기화 중 UI 비활성화
        isInputDisabled = true
        isResetting = true
        
        input = ""
        
        // 로딩 상태를 false로 설정 - 초기화 중에는 응답 생성 로딩 표시 안 함
        isLoading = false
        print("🚨 로딩 상태 OFF(초기화): \(isLoading)")
        
        Task {
            // 1. 기존 모델의 상태 초기화
            await bot.fullReset()
            
            // 2. 기존 인스턴스를 완전히 버리고 새 인스턴스 생성 및 chatHistory까지 초기화
            await MainActor.run {
                bot = LocalBot()
                chatHistory.removeAll()
                isInputDisabled = false
                isResetting = false
            }
            
            // KV 캐시 상태 업데이트 추가
            let cacheStatus = await bot.checkKVCacheStatus()
            await MainActor.run {
                bot.kvCacheInfo = cacheStatus
                bot.tokenCountInfo = "초기화 완료 (새 세션 시작)"
            }
            
            // 3. GC 힌트
            await Task.yield()
            
            print("✅ 대화 완전 초기화 완료")
        }
    }
}

// 메인 뷰
struct MainView: View {
    var body: some View {
        ChatView()
            .onAppear {
                print("📱 MainView가 화면에 나타남")
                print("🔍 앱 동작 상태를 확인하려면 콘솔 로그를 확인하세요")
            }
    }
} 
