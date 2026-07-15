import SwiftUI

struct AvatarMenuControl: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Change Avatar…") {
                model.chooseAvatar()
            }
            .accessibilityIdentifier("change-avatar")

            if let error = model.avatarImportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Avatar error: \(error)")
                    .accessibilityIdentifier("avatar-import-error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
