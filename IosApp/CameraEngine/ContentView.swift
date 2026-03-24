import SwiftUI
import Photos

struct ContentView: View {
    
    @StateObject private var camera = CameraManager()
    @State private var lastPhoto: UIImage? = nil
    @State private var isCapturing = false
    @State private var flashOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 상단 바
            ZStack {
                Color.black
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            
            // 카메라 뷰
            ZStack {
                Color.black
                
                if let preview = camera.previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                }
                
                // ✅ 플래시 깜빡임
                Color.white
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height - 350)
            .clipped()
            
            // 하단 바
            ZStack {
                Color.black
                
                HStack(alignment: .center) {
                    
                    Button {
                        openGallery()
                    } label: {
                        if let photo = lastPhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 52, height: 52)
                        }
                    }
                    
                    Spacer()
                    
                    Color.clear
                        .frame(width: 70, height: 70)
                    
                    Spacer()
                    
                    Button {
                        camera.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                
                VStack {
                    Circle()
                        .fill(isCapturing ? Color.gray : Color.white) // ✅ 촬영 중 회색
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 4)
                                .frame(width: 74, height: 74)
                        )
                        .onTapGesture {
                            guard !isCapturing else { return } // ✅ 연타 방지
                            isCapturing = true
                            camera.capturePhoto()
                            playFlash()
                        }
                    Spacer()
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
        }
        .ignoresSafeArea()
        .onAppear {
            camera.configure()
            loadLastPhoto()
        }
        .onChange(of: camera.capturedImage) { _ in
            loadLastPhoto()
        }
    }
    
    private func playFlash() {
        flashOpacity = 0

        // 번쩍
        withAnimation(.easeOut(duration: 0.08)) {
            flashOpacity = 0.95
        }
        // 사라짐
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeIn(duration: 0.18)) {
                flashOpacity = 0
            }
        }
        // 연타 방지 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            isCapturing = false
        }
    }
    
    func loadLastPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = result.firstObject else { return }
        
        let manager = PHImageManager.default()
        let size = CGSize(width: 100, height: 100)
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async {
                self.lastPhoto = image
            }
        }
    }
    
    func openGallery() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}
