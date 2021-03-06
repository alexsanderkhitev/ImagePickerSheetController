//
//  ImagePickerController.swift
//  ImagePickerSheet
//
//  Created by Laurin Brandner on 24/05/15.
//  Copyright (c) 2015 Laurin Brandner. All rights reserved.
//

import Foundation
import Photos

let previewInset: CGFloat = 5

/// The media type an instance of ImagePickerSheetController can display
public enum ImagePickerMediaType {
    case image
    case video
    case imageAndVideo
}

@objc public protocol ImagePickerSheetControllerDelegate {
    
    @objc optional func controllerWillEnlargePreview(_ controller: ImagePickerSheetController)
    @objc optional func controllerDidEnlargePreview(_ controller: ImagePickerSheetController)
    
    @objc optional func controller(_ controller: ImagePickerSheetController, willSelectAsset asset: PHAsset)
    @objc optional func controller(_ controller: ImagePickerSheetController, didSelectAsset asset: PHAsset)
    
    @objc optional func controller(_ controller: ImagePickerSheetController, willDeselectAsset asset: PHAsset)
    @objc optional func controller(_ controller: ImagePickerSheetController, didDeselectAsset asset: PHAsset)
    
}

@available(iOS 9.0, *)
open class ImagePickerSheetController: UIViewController {
    
    fileprivate lazy var sheetController: SheetController = {
        let controller = SheetController(previewCollectionView: self.previewPhotoCollectionView)
        controller.actionHandlingCallback = { [weak self] in
            self?.dismiss(animated: true, completion: { _ in
                // Possible retain cycle when action handlers hold a reference to the IPSC
                // Remove all actions to break it
                // TODO: - memory leaks
//                controller.removeAllActions()
            })
        }
        
        return controller
    }()
    
    var sheetCollectionView: UICollectionView {
        return sheetController.sheetCollectionView
    }
    
    
    fileprivate var previewPhotoCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 50, height: 50)
        layout.scrollDirection = .horizontal
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        return collectionView
    }()
    
    
    fileprivate var supplementaryViews = [Int: PreviewSupplementaryView]()
    
    lazy var backgroundView: UIView = {
        let view = UIView()
        view.accessibilityIdentifier = "ImagePickerSheetBackground"
        view.backgroundColor = UIColor(white: 0.0, alpha: 0.3961)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self.sheetController, action: #selector(SheetController.handleCancelAction)))
        
        return view
    }()
    
    open var delegate: ImagePickerSheetControllerDelegate?
    
    /// All the actions. The first action is shown at the top.
    open var actions: [ImagePickerAction] {
        return sheetController.actions
    }
    
    /// Maximum selection of images.
    open var maximumSelection: Int?
    
    fileprivate var selectedAssetIndices = [Int]() {
        didSet {
            sheetController.numberOfSelectedAssets = selectedAssetIndices.count
        }
    }
    
    
    /// The media type of the displayed assets
    open let mediaType: ImagePickerMediaType

    
    // MARK: - CollectionView identifier
    
    fileprivate let imagePickerCollectionCellIdentifier = "ImagePickerCollectionCell"
    fileprivate let imagePickerLiveCameraCollectionCellIdentifier = "ImagePickerLiveCameraCollectionCell"
    
    // MARK: - Data
    
    fileprivate var fetchResult: PHFetchResult<PHAsset>!
    
    // MARK: - Managers
    
    fileprivate let imageManager = PHCachingImageManager()
    
    // MARK: - Camera 
    
    fileprivate var cameraEngine = CameraEngine()
    fileprivate var isCameraControllerPreseneted = false
    
    // MARK: - Cells 
    
    fileprivate var cameraLiveCell: ImagePickerLiveCameraCollectionCell!
    
    
    /// Whether the image preview has been elarged. This is the case when at least once
    /// image has been selected.
    open fileprivate(set) var enlargedPreviews = false
    
    fileprivate let minimumPreviewHeight: CGFloat = 110 // 129
    fileprivate var maximumPreviewHeight: CGFloat = 110 // 129
    
    fileprivate var previewCheckmarkInset: CGFloat {
        return 12.5
    }
    
    // MARK: - Initialization
    
    public init(mediaType: ImagePickerMediaType) {
        self.mediaType = mediaType
        super.init(nibName: nil, bundle: nil)
        initialize()
    }

    public required init?(coder aDecoder: NSCoder) {
        self.mediaType = .imageAndVideo
        super.init(coder: aDecoder)
        initialize()
    }
    
    fileprivate func initialize() {
        modalPresentationStyle = .custom
        transitioningDelegate = self
        
        NotificationCenter.default.addObserver(sheetController, selector: #selector(SheetController.handleCancelAction), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }
    
    deinit {
        debugPrint("ImagePickerSheetController is deinit")
        NotificationCenter.default.removeObserver(sheetController, name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }
    
    // MARK: - View Lifecycle
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        // Camera
        cameraEngine.rotationCamera = true
        cameraEngine.currentDevice = .front
        cameraEngine.sessionPresset = .high
        cameraEngine.startSession()
        // UI
        addUIElements()
        // Collection view
        setupCollectionViewSettings()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preferredContentSize = CGSize(width: 400, height: view.frame.height)
        
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            prepareAssets()
        } else {
            // for camera
        }
        
        if isCameraControllerPreseneted {
            returnCameraLayerToCell()
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPhotoLibraryAccess()
    }
    
    // MARK: - Layout functions
    
    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    
    // MARK: - s
    
//    override open var shouldAutorotate: Bool {
//        return true
//    }
//    
//    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
//        return .all
//    }
    
  
    
    // MARK: - Actions
    
    /// Adds an new action.
    /// If the passed action is of type Cancel, any pre-existing Cancel actions will be removed.
    /// Always arranges the actions so that the Cancel action appears at the bottom.
    open func addAction(_ action: ImagePickerAction) {
        sheetController.addAction(action)
        view.setNeedsLayout()
    }
    
    // MARK: - UI
    
    private func addUIElements() {
        view.addSubview(backgroundView)
        view.addSubview(sheetCollectionView)
    }
    
    private func checkPhotoLibraryAccess() {
        if PHPhotoLibrary.authorizationStatus() == .notDetermined {
            PHPhotoLibrary.requestAuthorization() { status in
                if status == .authorized {
                    DispatchQueue.main.async {
                        self.prepareAssets()
                        self.previewPhotoCollectionView.reloadData()
                        self.sheetCollectionView.reloadData()
                        self.view.setNeedsLayout()
                        
                        // Explicitely disable animations so it wouldn't animate either
                        // if it was in a popover
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.view.layoutIfNeeded()
                        CATransaction.commit()
                    }
                }
            }
        }
    }
    
    // MARK: - Images
    
    fileprivate func prepareAssets() {
        requestPhoto()
        reloadCurrentPreviewHeight(invalidateLayout: false)
    }
    
    private func requestPhoto() {
        // If we get here without a segue, it's because we're visible at app launch,
        // so match the behavior of segue from the default "All Photos" view.
        if fetchResult == nil {
            let allPhotosOptions = PHFetchOptions()
            allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchResult = PHAsset.fetchAssets(with: .image, options: allPhotosOptions)
        }
    }
    
    // MARK: - Layout
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if popoverPresentationController == nil {
            // Offset necessary for expanded status bar
            // Bug in UIKit which doesn't reset the view's frame correctly
            
            let offset = UIApplication.shared.statusBarFrame.height
            var backgroundViewFrame = UIScreen.main.bounds
            backgroundViewFrame.origin.y = -offset
            backgroundViewFrame.size.height += offset
            backgroundView.frame = backgroundViewFrame
        }
        else {
            backgroundView.frame = view.bounds
        }
        
        reloadCurrentPreviewHeight(invalidateLayout: true)
        
        let sheetHeight = sheetController.preferredSheetHeight
        let sheetSize = CGSize(width: view.bounds.width, height: sheetHeight)
        
        // This particular order is necessary so that the sheet is layed out
        // correctly with and without an enclosing popover
        preferredContentSize = sheetSize
        sheetCollectionView.frame = CGRect(origin: CGPoint(x: view.bounds.minX, y: view.bounds.maxY - view.frame.origin.y - sheetHeight), size: sheetSize)
    }
    
    fileprivate func reloadCurrentPreviewHeight(invalidateLayout invalidate: Bool) {
        sheetController.setPreviewHeight(minimumPreviewHeight, invalidateLayout: invalidate)
    }
    
}

// MARK: - UICollection view 

extension ImagePickerSheetController {
    
    fileprivate func setupCollectionViewSettings() {
        previewPhotoCollectionView.dataSource = self
        previewPhotoCollectionView.delegate = self
        registerCollectionViewElements()
    }
    
    private func registerCollectionViewElements() {
        // cells
        let photoNib = UINib(nibName: "ImagePickerCollectionCell", bundle: Bundle(identifier: "com.SCImagePickerSheetController"))
        previewPhotoCollectionView.register(photoNib, forCellWithReuseIdentifier: imagePickerCollectionCellIdentifier)
        let liveNib = UINib(nibName: "ImagePickerLiveCameraCollectionCell", bundle: Bundle(identifier: "com.SCImagePickerSheetController"))
        previewPhotoCollectionView.register(liveNib, forCellWithReuseIdentifier: imagePickerLiveCameraCollectionCellIdentifier)
    }
    
    
}

// MARK: - UICollectionViewDataSource

extension ImagePickerSheetController: UICollectionViewDataSource {
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard fetchResult != nil else { return 1 }
        return 1
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard fetchResult != nil else { return 1 } // this is a camera }
        return fetchResult.count + 1
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.row == 0 {
            let cell = imagePickerLiveCameraCollectionCell(collectionView, indexPath: indexPath)
            
            cameraLiveCell = cell
            return cell
        } else {
            let cell = imagePickerCollectionCell(collectionView, indexPath: indexPath)
    
            
            return cell
        }
    }
    
}

// MARK: - UICollectionViewDelegate

extension ImagePickerSheetController: UICollectionViewDelegate {
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        debugPrint("didSelectItemAt")
        if indexPath.row == 0 {
            // this is a camera
            presentCameraController()
        }
        
//        delegate?.controller?(self, didSelectAsset: selectedAsset)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
      
    }
    
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ImagePickerSheetController: UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 95, height: 95)
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    
}

// MARK: - UICollectionView cells 

extension ImagePickerSheetController {
    
    fileprivate func imagePickerCollectionCell(_ collectionView: UICollectionView, indexPath: IndexPath) -> ImagePickerCollectionCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: imagePickerCollectionCellIdentifier, for: indexPath) as! ImagePickerCollectionCell
        
        guard fetchResult != nil else { return cell }
        let asset = fetchResult.object(at: indexPath.row - 1) //- 1) - 1 because camera view
        
        cell.representedAssetIdentifier = asset.localIdentifier
        imageManager.requestImage(for: asset, targetSize: CGSize(width: 95, height: 95), contentMode: .aspectFill, options: nil) { (image, info) in
            if cell.representedAssetIdentifier == asset.localIdentifier {
                cell.photoImageView?.image = image
            }
        }
        
        return cell
    }
    
    fileprivate func imagePickerLiveCameraCollectionCell(_ collectionView: UICollectionView, indexPath: IndexPath) -> ImagePickerLiveCameraCollectionCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: imagePickerLiveCameraCollectionCellIdentifier, for: indexPath) as! ImagePickerLiveCameraCollectionCell
        
        cameraEngine.previewLayer.frame = CGRect(x: 0, y: 0, width: 95, height: 95)
        
        // camera orientation
        
        cameraEngine.previewLayer.connection.videoOrientation = AVCaptureVideoOrientation.orientationFromUIDeviceOrientation(UIDevice.current.orientation)

        
        cell.containerView.layer.addSublayer(cameraEngine.previewLayer)
        return cell
    }
    
}

// MARK: - UIViewControllerTransitioningDelegate

extension ImagePickerSheetController: UIViewControllerTransitioningDelegate {
    
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerSheetController: self, presenting: true)
    }
    
    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerSheetController: self, presenting: false)
    }
    
}

// MARK: - Camera

extension ImagePickerSheetController {
    
    fileprivate func presentCameraController() {
        let cameraController = CameraControllerViewController()
        cameraController.cameraEngine = cameraEngine
        cameraController.cameraLayer = cameraEngine.previewLayer
        cameraEngine.previewLayer.connection.videoOrientation = .portrait// AVCaptureVideoOrientation.orientationFromUIDeviceOrientation(UIDevice.current.orientation)
        cameraEngine.rotationCamera = false
                
        present(cameraController, animated: false, completion: { [weak self] in

                })
        isCameraControllerPreseneted = true
    }

    
    fileprivate func returnCameraLayerToCell() {
        if isCameraControllerPreseneted == true {
            guard let cameraLiveCell = previewPhotoCollectionView.cellForItem(at: IndexPath(row: 0, section: 0)) as? ImagePickerLiveCameraCollectionCell else { return }
            cameraEngine.rotationCamera = true
            cameraEngine.previewLayer.frame = CGRect(x: 0, y: 0, width: 95, height: 95)
            
            
            if let sublayers = cameraLiveCell.containerView.layer.sublayers {
                for sublayer in sublayers {
                    if sublayer.isKind(of: AVCaptureVideoPreviewLayer.self) {
                        sublayer.removeFromSuperlayer()
                    }
                }
            }
            
            cameraLiveCell.containerView.layer.insertSublayer(cameraEngine.previewLayer, at: 1)
        }
    }
    
    fileprivate func presentImagePicker() {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.cameraDevice = .front
        
        guard let cameraLiveCell = previewPhotoCollectionView.cellForItem(at: IndexPath(row: 0, section: 0)) as? ImagePickerLiveCameraCollectionCell else { return }
        let heroID = "LiveHero"        
        
        present(imagePicker, animated: true, completion: nil)
    }
    
}
