import SwiftUI
import SwiftUINavigation

struct RootView: View {
  var body: some View {
    let _ = print("!!!!!!")
    UIViewControllerRepresenting {
      StaticNavigationStackController()
    }
//    NavigationStack {
//      List {
//        NavigationLink("SwiftUI") {
//          SwiftUICaseStudiesView()
//        }
//        NavigationLink("UIKit") {
//          UIKitCaseStudiesView()
//        }
//      }
//      .navigationTitle("Case studies")
//    }
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
