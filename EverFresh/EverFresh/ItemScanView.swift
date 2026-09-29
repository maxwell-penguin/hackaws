import SwiftUI
import PhotosUI

enum ScanMode: String, CaseIterable {
    case foodItem = "Food Item"
    case receipt = "Receipt"
}

struct ItemScanView: View {
    @State private var mode: ScanMode = .foodItem
    @State private var isShowingSourceOptions = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotosPicker = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var scannedItem: ScannedItem?
    @State private var receiptItems: [ScannedItem] = []
    @State private var isShowingReceiptReview = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var promptText: String {
        switch mode {
        case .foodItem: return "Scan a food item to add it to your fridge."
        case .receipt: return "Scan a receipt to add everything on it at once."
        }
    }

    private var buttonLabel: String {
        switch mode {
        case .foodItem: return "Scan Item"
        case .receipt: return "Scan Receipt"
        }
    }

    private var uploadingMessage: String {
        switch mode {
        case .foodItem: return "Scanning item…"
        case .receipt: return "Scanning receipt…"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Mode", selection: $mode) {
                    ForEach(ScanMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Spacer()
                if isUploading {
                    ProgressView(uploadingMessage)
                } else {
                    Image(systemName: mode == .foodItem ? "camera.viewfinder" : "receipt")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text(promptText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button {
                        isShowingSourceOptions = true
                    } label: {
                        Label(buttonLabel, systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                }
                Spacer()
            }
            .navigationTitle("Add Item")
            .confirmationDialog("Add a photo", isPresented: $isShowingSourceOptions, titleVisibility: .visible) {
                if isCameraAvailable {
                    Button("Take Photo") { isShowingCamera = true }
                }
                Button("Choose from Library") { isShowingPhotosPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $isShowingPhotosPicker, selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        errorMessage = "Couldn't load the selected photo."
                        showError = true
                        return
                    }
                    photosPickerItem = nil
                    await upload(image: image)
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(
                    onImagePicked: { image in
                        isShowingCamera = false
                        Task { await upload(image: image) }
                    },
                    onCancel: { isShowingCamera = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $scannedItem) { item in
                ItemConfirmationView(item: item)
            }
            .sheet(isPresented: $isShowingReceiptReview) {
                ReceiptReviewFlow(items: receiptItems)
            }
            .alert("Couldn't scan item", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func upload(image: UIImage) async {
        isUploading = true
        defer { isUploading = false }
        do {
            switch mode {
            case .foodItem:
                scannedItem = try await ItemService.scanItem(image: image)
            case .receipt:
                receiptItems = try await ItemService.scanReceipt(image: image)
                isShowingReceiptReview = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    ItemScanView()
        .environmentObject(AppState())
}
