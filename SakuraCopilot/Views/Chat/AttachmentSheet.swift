import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 附件入口（文件 / 拍照 / 相册 → iOS 原生 OCR）
struct AttachmentSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 16) {
                Capsule().fill(CyberTheme.stroke).frame(width: 40, height: 4).padding(.top, 10)
                SectionTitle(text: "添加附件（OCR 用 iOS 原生识别）", icon: "paperclip")

                if busy {
                    GlowCard {
                        VStack(spacing: 8) {
                            ProgressView().tint(CyberTheme.neonPink)
                            Text(status.isBlank ? "处理中…" : status)
                                .font(.cyber(12)).foregroundStyle(CyberTheme.textSec)
                        }
                        .frame(maxWidth: .infinity).padding(14)
                    }
                }

                HStack(spacing: 10) {
                    attachButton(icon: "folder", title: "文件", tint: CyberTheme.neonCyan) { showFileImporter = true }
                    attachButton(icon: "camera", title: "拍照", tint: CyberTheme.sakura) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                        else { status = "当前设备无相机（模拟器），请用相册或文件" }
                    }
                    attachButton(icon: "photo.on.rectangle", title: "相册", tint: CyberTheme.neonPurple) {}
                }
                .photosPicker(isPresented: Binding(get: { false }, set: { _ in }), selection: $photoItem, matching: .images)

                if !services.chat.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "已添加 \(services.chat.attachments.count) 个附件", icon: "checkmark.circle")
                        ForEach(services.chat.attachments) { att in
                            HStack {
                                Label(att.name, systemImage: "doc")
                                    .font(.cyber(12)).foregroundStyle(CyberTheme.textPri).lineLimit(1)
                                Spacer()
                                Button {
                                    services.chat.attachments.removeAll { $0.id == att.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(CyberTheme.textFaint)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg1))
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await importFiles(urls) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await handleImage(image, name: "拍照-\(Self.stamp()).jpg") }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    busy = true
                    status = "读取图片…"
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let name = item.itemIdentifier ?? "IMG-\(Self.stamp())"
                        await handleImageData(data, name: name)
                    }
                    busy = false
                    photoItem = nil
                }
            }
        }
    }

    private func attachButton(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            if icon == "photo.on.rectangle" {
                // photosPicker 通过 selection 绑定触发：直接挑起相册
                photoItem = nil
                openPhotos()
            } else { action() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium))
                Text(title).font(.cyber(12, .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 14).fill(CyberTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    @State private var photosTrigger = false

    private func openPhotos() {
        photosTrigger = true
    }

    private func importFiles(_ urls: [URL]) async {
        busy = true
        for url in urls {
            status = "导入 \(url.lastPathComponent)…"
            if let text = try? await TextExtractor.extract(url: url), !text.isBlank {
                services.chat.attachments.append(.text(url.lastPathComponent, text))
            }
        }
        busy = false
        status = ""
    }

    private func handleImage(_ image: UIImage, name: String) async {
        busy = true
        status = "iOS 原生 OCR 识别中…"
        if let data = image.jpegData(compressionQuality: 0.9) {
            await handleImageData(data, name: name)
        }
        busy = false
    }

    private func handleImageData(_ data: Data, name: String) async {
        status = "iOS 原生 OCR 识别中…"
        let text = await OCRService.recognizeText(in: data)
        if text.isBlank {
            status = "未识别到文字"
            return
        }
        services.chat.attachments.append(.text(name + "·OCR", text))
        status = "已识别 \(text.count) 字"
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - 相机
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.dismiss()
                parent.onImage(image)
            } else {
                parent.dismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
