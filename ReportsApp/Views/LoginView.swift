import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BrandColors.teal, Color.accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Image("LoginIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)

                    Text("IAR Housing Hub")
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    Text("Sign in with your member account to access reports and dashboards.")
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    auth.startLogin()
                } label: {
                    Text("Sign in")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(BrandColors.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 32)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)

                Spacer()

                Text("Indiana Association of REALTORS®")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 20)
            }
        }
    }
}
