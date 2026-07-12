import SwiftUI
import AppKit

protocol MascotAssetProviding { func assetName(for state: AgentSessionState) -> String }
struct DefaultMascotAssets: MascotAssetProviding {
    func assetName(for state: AgentSessionState) -> String { switch state { case .idle,.ended:"MascotIdle";case .working:"MascotWorking";case .needsInput,.error:"MascotNeedsInput" } }
}
struct StaticMascotView:View {
    let state:AgentSessionState
    let assets:any MascotAssetProviding
    init(state:AgentSessionState,assets:any MascotAssetProviding=DefaultMascotAssets()){self.state=state;self.assets=assets}
    var body:some View { ZStack { if let url=Bundle.module.url(forResource:assets.assetName(for:state),withExtension:"svg",subdirectory:"Mascots"),let image=NSImage(contentsOf:url){Image(nsImage:image).resizable().scaledToFit().frame(width:112,height:112)}else{Color.clear.frame(width:112,height:112)};if state == .error{Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.red).offset(x:45,y:-45)}}.accessibilityLabel("Morphling \(state.rawValue)") }
}
