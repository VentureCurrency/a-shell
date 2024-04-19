//
//  ContentView.swift
//  a-Shell
//
//  Created by Nicolas Holzschuch on 30/06/2019.
//  Copyright © 2019 AsheKube. All rights reserved.
//

#if WebView_Version

import SwiftUI
import WebKit

// SwiftUI extension for fullscreen rendering
public enum ViewBehavior: Int {
    case original
    case ignoreSafeArea
    case fullScreen
}

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

public var toolbarShouldBeShown = true
public var useSystemToolbar = false
public var showToolbar = true
public var showKeyboardAtStartup = true
// .fullScreen is too much for floating KB + toolbar, ignoreSafeArea seems to work,
// automatic detection causes blank screen when switching back-forth
// Make this a user-defined setup, with "ignoreSafeArea" the default.
public var viewBehavior: ViewBehavior = .ignoreSafeArea

struct Webview : UIViewRepresentable {
    typealias WebViewType = KBWebViewBase

    let webView: WebViewType

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        if #available(iOS 14.5, *) {
            config.preferences.isTextInteractionEnabled = true
        }
        config.preferences.setValue(true as Bool, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true as Bool, forKey: "allowUniversalAccessFromFileURLs")
        // Does not change anything either way (??? !!!)
        config.preferences.setValue(true as Bool, forKey: "shouldAllowUserInstalledFonts")
        config.selectionGranularity = .character; // Could be .dynamic
        // let preferences = WKWebpagePreferences()
        // preferences.allowsContentJavaScript = true
        webView = .init(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        if #available(iOS 15.0, *) {
            webView.keyboardLayoutGuide.topAnchor.constraint(equalTo: webView.bottomAnchor).isActive = true
            // This is necessary to allow the various edge constraints to engage.
            webView.keyboardLayoutGuide.followsUndockedKeyboard = true
        }
    }
    
    func makeUIView(context: Context) -> WebViewType {
        return webView
    }

    func updateUIView(_ uiView: WebViewType, context: Context) {
        if (uiView.url != nil) { return } // Already loaded the page
        let htermFilePath = Bundle.main.path(forResource: "hterm", ofType: "html")
        uiView.isOpaque = false
        uiView.loadFileURL(URL(fileURLWithPath: htermFilePath!), allowingReadAccessTo: URL(fileURLWithPath: htermFilePath!))
    }
}


struct ContentView: View {
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardWidth: CGFloat = 0
    // @State private var viewBehavior: ViewBehavior = .ignoreSafeArea
    
    let webview = Webview()
    
    // Adapt window size to keyboard height, see:
    // https://stackoverflow.com/questions/56491881/move-textfield-up-when-thekeyboard-has-appeared-by-using-swiftui-ios
    // A publisher that combines all of the relevant keyboard changing notifications and maps them into a `CGFloat` representing the new height of the
    // keyboard rect.
    private let keyboardChangePublisher = NotificationCenter.Publisher(center: .default,
                                                                       name: UIResponder.keyboardWillShowNotification)
        .merge(with: NotificationCenter.Publisher(center: .default,
                                                  name: UIResponder.keyboardWillChangeFrameNotification))
        .merge(with: NotificationCenter.Publisher(center: .default,
                                                  name: UIResponder.keyboardWillHideNotification)
               // But we don't want to pass the keyboard rect from keyboardWillHide, so strip the userInfo out before
               // passing the notification on.
            .map { Notification(name: $0.name, object: $0.object, userInfo: nil) })
    // Now map the merged notification stream into a height value.
        .map { (note) -> CGFloat in
            let height = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).size.height
            let width = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).size.width
            let x = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).origin.x
            let y = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).origin.y
            let userInfo = note.userInfo
            // NSLog("Received \(note.name.rawValue) with height \(height) width \(width) origin: \(x) -- \(y)")
            // if (height > 200) && (x > 0) {
            //     NSLog("Undetected floating keyboard detected")
            // }
            // We have no way to make the difference between "no keyboard on screen" and "external kb connected"
            // (some BT keyboards do not register as such) (also floating keyboards have null height)
            // height == 0 ==> there's probably a keyboard, but we didn't detect it.
            // height != 0 ==> there is a keyboard, and iOS did detect it, so no need to change the height.
            // A bit counter-intuitive, but it works.
            // Except sometimes with a floating keyboard, we get h = 324 and view not set.
            if (height == 0) && showToolbar { return 40 } // At least the size of the toolbar -- if no keyboard present
            // Floating window detected (at least on iPad Pro 12.9). 40 is too much, 20 not enough.
            else if (height == 60) { // floating window detected, external keyboard
                return 20
            }
            else if (height > 200) && (x > 0) && showToolbar {
                return 40
            } // Floating keyboard not detected
            else { return 0 } // SwiftUI has done its job and returned the proper keyboard size.
        }
    
    var body: some View {
        // resize depending on keyboard. Specify size (.frame) instead of padding.
        webview.onReceive(keyboardChangePublisher) {
            self.keyboardHeight = $0
            // NSLog("keyboardHeight: \(keyboardHeight)")
            // NSLog("Bounds \(webview.webView.coordinateSpace.bounds)")
            // NSLog("Screen \(UIScreen.main.bounds)")
        }
        .padding(.top, 0) // Important, to set the size of the view
        .if(viewBehavior == .original || viewBehavior == .ignoreSafeArea) {
            // If not displaying hterm and not displaying the keyboard, hide the space for the toolbar
            if (webview.webView.url?.path != Bundle.main.resourcePath! + "/hterm.html") && (keyboardHeight <= 40) {
                $0.padding(.bottom, 0)
            } else {
                $0.padding(.bottom, keyboardHeight)
            }
        }
        .if((viewBehavior == .ignoreSafeArea || viewBehavior == .fullScreen)) {
            $0.ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
        }
    }
}
#endif
