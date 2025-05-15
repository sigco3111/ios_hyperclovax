//
//  ContentView.swift
//  gemma3
//
//  Created by hjshin on 5/9/25.
//

import SwiftUI

// ⚠️ 주의: 이 파일은 더 이상 앱에서 사용되지 않으며 참조용으로만 유지됩니다.
// ⚠️ 실제 앱은 MainView.swift를 사용합니다.

// 참조용 예제 뷰
struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("⚠️ 참조용 파일")
                .font(.headline)
                .padding()
            
            Text("이 파일은 참조용으로만 유지됩니다.\n실제 앱은 MainView.swift를 사용합니다.")
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
} 