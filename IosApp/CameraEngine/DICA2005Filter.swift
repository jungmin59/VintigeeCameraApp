    import CoreImage
    import MetalKit
    import UIKit

    class DICA2005Filter {
        
        private let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let pipelineState: MTLComputePipelineState
        private let ciContext: CIContext
        private var lutTexture: MTLTexture?
        
        init?() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else { return nil }
            self.device = device
            self.commandQueue = queue
            self.ciContext = CIContext(mtlDevice: device)
            
            guard let library = device.makeDefaultLibrary(),
                  let function = library.makeFunction(name: "dica2005Filter"),
                  let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
            self.pipelineState = pipeline
            
            self.lutTexture = Self.loadLUT(named: "DICA2005", device: device)
        }
        
        // MARK: - .cube 파일 파싱 + 3D MTLTexture 생성
        private static func loadLUT(named name: String, device: MTLDevice) -> MTLTexture? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "cube"),
                  let content = try? String(contentsOf: url) else {
                print("LUT 파일을 찾을 수 없어: \(name).cube")
                return nil
            }
            
            var size = 0
            var data: [Float] = []
            
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // 주석, 빈 줄 스킵
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                
                // LUT 크기 파싱
                if trimmed.hasPrefix("LUT_3D_SIZE") {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if let s = parts.last, let n = Int(s) {
                        size = n
                    }
                    continue
                }
                
                // DOMAIN, TITLE 등 스킵
                if trimmed.hasPrefix("TITLE") ||
                   trimmed.hasPrefix("DOMAIN") ||
                   trimmed.hasPrefix("LUT_1D") { continue }
                
                // RGB 데이터 파싱
                let values = trimmed.components(separatedBy: .whitespaces).compactMap { Float($0) }
                if values.count == 3 {
                    data.append(values[0]) // R
                    data.append(values[1]) // G
                    data.append(values[2]) // B
                    data.append(1.0)       // A
                }
            }
            
            guard size > 0, data.count == size * size * size * 4 else {
                print("LUT 파싱 실패: size=\(size), dataCount=\(data.count)")
                return nil
            }
            
            // 3D MTLTexture 생성
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D
            descriptor.pixelFormat = .rgba32Float
            descriptor.width  = size
            descriptor.height = size
            descriptor.depth  = size
            descriptor.usage  = .shaderRead
            descriptor.storageMode = .shared
            
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                print("3D 텍스처 생성 실패")
                return nil
            }
            
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size:   MTLSize(width: size, height: size, depth: size)
            )
            
            data.withUnsafeBytes { ptr in
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    slice: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: size * 4 * MemoryLayout<Float>.size,
                    bytesPerImage: size * size * 4 * MemoryLayout<Float>.size
                )
            }
            
            print("LUT 로드 성공: \(name).cube / size=\(size)")
            return texture
        }
        
        // MARK: - 필터 적용
        func apply(to inputImage: UIImage) -> UIImage {
            guard let cgImage = inputImage.cgImage else { return inputImage }
            
            let textureLoader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [.SRGB: true]
            guard let inTexture = try? textureLoader.newTexture(cgImage: cgImage, options: options) else { return inputImage }
            
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: inTexture.width,
                height: inTexture.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderWrite, .shaderRead]
            
            guard let outTexture = device.makeTexture(descriptor: descriptor),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else { return inputImage }
            
            encoder.setComputePipelineState(pipelineState)
            encoder.setTexture(inTexture,  index: 0)
            encoder.setTexture(outTexture, index: 1)
            encoder.setTexture(lutTexture, index: 2)
            
            let w = 16, h = 16
            let threadGroupSize = MTLSize(width: w, height: h, depth: 1)
            let threadGroups = MTLSize(
                width:  (inTexture.width  + w - 1) / w,
                height: (inTexture.height + h - 1) / h,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            guard let ci = CIImage(mtlTexture: outTexture, options: nil) else { return inputImage }
            let flipped = ci.oriented(.downMirrored)
            guard let cgOut = ciContext.createCGImage(flipped, from: flipped.extent) else { return inputImage }
            return UIImage(cgImage: cgOut, scale: inputImage.scale, orientation: inputImage.imageOrientation)
        }
    }
