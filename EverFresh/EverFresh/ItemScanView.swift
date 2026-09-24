import SwiftUI
import PhotosUI

struct ItemScanView: View {
    @State private var isShowingSourceOptions = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotosPicker = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var scannedItem: ScannedItem?
    @State private var showError = false
    @State private var errorMessage = ""

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                if isUploading {
                    ProgressView("Scanning item…")
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Scan a food item to add it to your fridge.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button {
                        isShowingSourceOptions = true
                    } label: {
                        Label("Scan Item", systemImage: "camera")
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
            scannedItem = try await ItemService.scanItem(image: image)
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
