//
//  PsbtTableViewController.swift
//  GordianSigner
//
//  Created by Peter on 11/12/20.
//  Copyright © 2020 Blockchain Commons. All rights reserved.
//

import UIKit
import LibWally

class PsbtTableViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak private var tableView: UITableView!
    @IBOutlet weak private var signButtonOutlet: UIButton!
    
    private var spinner = Spinner()
    var psbtText = ""
    var rawTx = ""
    var psbt:PSBT!
    private var canSign = false
    private var export = false
    private var alertStyle = UIAlertController.Style.actionSheet
    var inputsArray = [[String:Any]]()
    var signedFor = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorColor = .lightGray
        
        signButtonOutlet.layer.cornerRadius = 8
        
        if (UIDevice.current.userInterfaceIdiom == .pad) {
          alertStyle = UIAlertController.Style.alert
        }
        
        if psbtText != "" {
            psbt = try? PSBT(psbtText, .testnet)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        load { success in
            if success {
                DispatchQueue.main.async { [weak self] in
                    self?.tableView.reloadData()
                }
            }
        }
    }
    
    private func load(completion: @escaping ((Bool) -> Void)) {
        inputsArray.removeAll()
        
        let inputs = self.psbt.inputs
        
        for (i, input) in inputs.enumerated() {
            var pubkeysArray = [[String:Any]]()
            self.inputsArray.append(["input": input])
            
            guard let origins = input.origins else { completion(false); return }
            
            for (o, origin) in origins.enumerated() {
                let pubkey = origin.key.data.hexString
                
                guard let path = try? origin.value.path.chop(4) else { completion(false); return }
                
                let dict = ["pubkey":pubkey, "hasSigned": false, "keysetLabel": "unknown", "path": path, "fullPath": origin.value.path] as [String : Any]
                pubkeysArray.append(dict)
                
                if o + 1 == origins.count {
                    self.inputsArray[i]["pubKeyArray"] = pubkeysArray
                }
                
                if i + 1 == inputs.count && o + 1 == origins.count {
                    self.parsePubkeys(completion: completion)
                }
            }
        }
    }
    
    private func parsePubkeys(completion: @escaping ((Bool) -> Void)) {
        CoreDataService.retrieveEntity(entityName: .keyset) { [weak self] (keysets, errorDescription) in
            guard let self = self else { return }
            
            guard let keysets = keysets, keysets.count > 0 else { completion(false); return }
            
            for (i, inputDictArray) in self.inputsArray.enumerated() {
                let input = inputDictArray["input"] as! PSBTInput
                var pubkeyArray = inputDictArray["pubKeyArray"] as! [[String:Any]]
                
                for (p, pubkeyDict) in pubkeyArray.enumerated() {
                    var updatedDict = pubkeyDict
                    
                    let originalPubkey = pubkeyDict["pubkey"] as! String
                    let path = pubkeyDict["path"] as! BIP32Path
                    let fullPath = pubkeyDict["fullPath"] as! BIP32Path
                    
                    CoreDataService.retrieveEntity(entityName: .signer) { (signers, errorDescription) in
                        if let signers = signers, signers.count > 0 {
                            
                            for signer in signers {
                                let signerStruct = SignerStruct(dictionary: signer)
                                if let entropy = signerStruct.entropy {
                                    if let decryptedEntropy = Encryption.decrypt(entropy) {
                                        let e = BIP39Entropy(decryptedEntropy)
                                        if let mnemonic = BIP39Mnemonic(e) {
                                            var passphrase = ""
                                            if let encryptedPassphrase = signerStruct.passphrase {
                                                if let decryptedPassphrase = Encryption.decrypt(encryptedPassphrase) {
                                                    passphrase = decryptedPassphrase.utf8
                                                }
                                            }
                                            
                                            let seedHex = mnemonic.seedHex(passphrase)
                                            
                                            if let hdMasterKey = HDKey(seedHex, .testnet) {
                                                if let childKey = try? hdMasterKey.derive(fullPath) {
                                                    if childKey.pubKey.data.hexString == originalPubkey {
                                                        self.canSign = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    for (k, keyset) in keysets.enumerated() {
                        let keysetStruct = KeysetStruct(dictionary: keyset)
                        
                        if let descriptor = keysetStruct.bip48SegwitAccount {
                            let arr = descriptor.split(separator: "]")
                            var xpub = ""
                            
                            if arr.count > 0 {
                                xpub = "\(arr[1])"
                            }
                            
                            if let hdkey = HDKey(xpub), let childKey = try? hdkey.derive(path) {
                                
                                if originalPubkey == childKey.pubKey.data.hexString {
                                    updatedDict["keysetLabel"] = keysetStruct.label
                                    pubkeyArray[p] = updatedDict
                                    
                                    if let sigs = input.signatures {
                                        
                                        for (s, sig) in sigs.enumerated() {
                                            let signedKey = sig.key.data.hexString
                                            
                                            if signedKey == originalPubkey {
                                                updatedDict["hasSigned"] = true
                                                pubkeyArray[p] = updatedDict
                                                self.inputsArray[i]["pubKeyArray"] = pubkeyArray
                                            }
                                                                                                                                    
                                            if self.signedFor.count > 0 {
                                                
                                                for (x, signed) in self.signedFor.enumerated() {
                                                    
                                                    if signed == originalPubkey {
                                                        updatedDict["hasSigned"] = true
                                                        pubkeyArray[p] = updatedDict
                                                        self.inputsArray[i]["pubKeyArray"] = pubkeyArray
                                                    }
                                                    
                                                    if k + 1 == keysets.count && p + 1 == pubkeyArray.count && i + 1 == self.inputsArray.count && s + 1 == sigs.count && x + 1 == self.signedFor.count {
                                                        completion(true)
                                                    }
                                                }
                                                
                                            } else {
                                                
                                                if k + 1 == keysets.count && p + 1 == pubkeyArray.count && i + 1 == self.inputsArray.count && s + 1 == sigs.count {
                                                    completion(true)
                                                }
                                            }
                                        }
                                        
                                    } else {
                                        self.inputsArray[i]["pubKeyArray"] = pubkeyArray
                                        
                                        if k + 1 == keysets.count && p + 1 == pubkeyArray.count && i + 1 == self.inputsArray.count {
                                            completion(true)
                                        }
                                    }
                                    
                                } else {
                                    
                                    if k + 1 == keysets.count && p + 1 == pubkeyArray.count && i + 1 == self.inputsArray.count {
                                        print("finishing here")
                                        completion(true)
                                    }
                                }
                                
                            } else {
                                
                                if k + 1 == keysets.count && p + 1 == pubkeyArray.count && i + 1 == self.inputsArray.count {
                                    completion(true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func signAction(_ sender: Any) {
        if !export {
            if canSign {
                sign(nil)
            } else {
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    let alert = UIAlertController(title: "No private keys to sign with", message: "You can add a signer now to sign this psbt. You can opt of storing the private keys and we will only temporarily use the signer to sign this psbt.", preferredStyle: self.alertStyle)
                    
                    alert.addAction(UIAlertAction(title: "add signer", style: .default, handler: { action in
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            self.performSegue(withIdentifier: "segueToSign", sender: self)
                        }
                    }))
                    
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
                    alert.popoverPresentationController?.sourceView = self.view
                    self.present(alert, animated: true) {}
                }
            }
        } else {
            exportAction()
        }
    }
    
    @IBAction func exportAction(_ sender: Any) {
        exportAction()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 1:
            return psbt.inputs.count
        case 2:
            return psbt.outputs.count
        default:
            return 1
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            return completeCell(indexPath)
        case 1:
            if inputsArray.count > 0 {
                return inputCell(indexPath)
            } else {
                return UITableViewCell()
            }
        case 2:
            return outputCell(indexPath)
        case 3:
            return feeCell(indexPath)
        default:
            return UITableViewCell()
        }
    }
    
    private func configureCell(_ cell: UITableViewCell) {
        cell.clipsToBounds = true
        cell.layer.cornerRadius = 8
        cell.selectionStyle = .none
    }
    
    private func configureView(_ view: UIView) {
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
    }
    
    private func completeCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "completeCell", for: indexPath)
        configureCell(cell)
        
        let label = cell.viewWithTag(1) as! UILabel
        let icon = cell.viewWithTag(2) as! UIImageView
        
        var psbtToFinalize = psbt!
        
        if psbtToFinalize.finalize() {
            if psbtToFinalize.complete {
                if let _ = psbtToFinalize.transactionFinal {
                    label.text = "PSBT complete"
                    icon.image = UIImage(systemName: "checkmark.square")
                    icon.tintColor = .systemGreen
                }
            } else {
                label.text = "PSBT incomplete"
                icon.image = UIImage(systemName: "exclamationmark.square")
                icon.tintColor = .systemPink
            }
        } else {
            if psbtToFinalize.complete {
                label.text = "PSBT complete"
                icon.image = UIImage(systemName: "checkmark.square")
                icon.tintColor = .systemGreen
            } else {
                label.text = "PSBT incomplete"
                icon.image = UIImage(systemName: "exclamationmark.square")
                icon.tintColor = .systemPink
            }
        }
        
        return cell
    }
    
    private func inputCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "inputCell", for: indexPath)
        configureCell(cell)
        
        let isMineImageView = cell.viewWithTag(1) as! UIImageView
        let amountLabel = cell.viewWithTag(2) as! UILabel
        let participantsTextView = cell.viewWithTag(3) as! UITextView
        let numberOfSigsLabel = cell.viewWithTag(6) as! UILabel
        let inputNumberLabel = cell.viewWithTag(7) as! UILabel
        
        inputNumberLabel.text = "Input #\(indexPath.row + 1)"
        
        configureView(isMineImageView)
        configureView(participantsTextView)
        
        let inputDict = inputsArray[indexPath.row]
        let input = inputDict["input"] as! PSBTInput
        
        let pubkeyArray = inputDict["pubKeyArray"] as! [[String:Any]]
                
        var isMine = false
        
        participantsTextView.text = ""
        numberOfSigsLabel.text = "?"
        
        if pubkeyArray.count > 0 {
            var numberOfSigs = 0
            
            for pubkey in pubkeyArray {
                let participant = pubkey["keysetLabel"] as! String
                let hasSigned = pubkey["hasSigned"] as! Bool
                
                if hasSigned {
                    participantsTextView.text += "Signed: " + participant + "\n"
                    numberOfSigs += 1
                } else {
                    participantsTextView.text += "NOT signed: " + participant + "\n"
                }
                
                if participant != "unknown" {
                    isMine = true
                }
            }
            
            if isMine {
                isMineImageView.image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")
                isMineImageView.tintColor = .systemGreen
            } else {
                isMineImageView.image = UIImage(systemName: "questionmark.circle")
                isMineImageView.tintColor = .systemGray
            }
            
            numberOfSigsLabel.text = "\(numberOfSigs) signatures"
            
        } else {
            isMineImageView.image = UIImage(systemName: "questionmark.circle")
            isMineImageView.tintColor = .systemGray
            numberOfSigsLabel.text = "?"
        }
        
        if let amount = input.amount {
            amountLabel.text = "\(Double(amount) / 100000000.0) btc"
        }
        
        return cell
    }
    
    private func outputCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "outputCell", for: indexPath)
        configureCell(cell)
        
        let outputLabel = cell.viewWithTag(1) as! UILabel
        let isMineImageView = cell.viewWithTag(2) as! UIImageView
        let amountLabel = cell.viewWithTag(3) as! UILabel
        let addressLabel = cell.viewWithTag(4) as! UILabel
        
        let output = psbt.outputs[indexPath.row]
        
        outputLabel.text = "Output #\(indexPath.row + 1)"
        
        isMineImageView.image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")
        isMineImageView.tintColor = .systemGreen
        
        amountLabel.text = (Double(output.txOutput.amount) / 100000000.0).avoidNotation + " btc"
        
        if let address = output.txOutput.address {
            addressLabel.text = address
        } else {
            addressLabel.text = "no address..."
        }
        
        addressLabel.adjustsFontSizeToFitWidth = true
        
        return cell
    }
    
    private func feeCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "feeCell", for: indexPath)
        configureCell(cell)
        
        let feeLabel = cell.viewWithTag(1) as! UILabel
        if let fee = psbt.fee {
            feeLabel.text = "\((Double(fee) / 100000000.0).avoidNotation) btc / \(fee) sats"
        } else {
            feeLabel.text = "No fee available..."
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0:
            return 44
        case 1:
            return 168
        case 2:
            return 107
        case 3:
            return 44
        default:
            return 80
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = UIColor.clear
        header.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - 32, height: 50)
        
        let textLabel = UILabel()
        textLabel.textAlignment = .left
        textLabel.font = UIFont.systemFont(ofSize: 20, weight: .regular)
        textLabel.textColor = .white
        textLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
        
        switch section {
        case 0:
            textLabel.text = "Status"
        case 1:
            textLabel.text = "Inputs"
        case 2:
            textLabel.text = "Outputs"
        case 3:
            textLabel.text = "Mining Fee"
        default:
            break
        }
        
        header.addSubview(textLabel)
        return header
    }
    
    private func sign(_ mk: HDKey?) {
        if psbt != nil {
            spinner.add(vc: self, description: "signing")
            
            PSBTSigner.sign(psbt.description, mk) { [weak self] (signedPsbt, signedFor, errorMessage) in
                guard let self = self else { return }
                
                guard let signedPsbt = signedPsbt, let signedFor = signedFor else {
                    self.spinner.remove()
                    showAlert(self, "Something is not right...", errorMessage ?? "unable to sign that psbt: unknown error")
                    return
                }
                
                self.signedFor = signedFor
                
                var psbtToFinalize = signedPsbt
                
                if psbtToFinalize.finalize() {
                    if psbtToFinalize.complete {
                        if let final = psbtToFinalize.transactionFinal {
                            if let hex = final.description {
                                self.rawTx = hex
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.export = true
                    self.psbt = signedPsbt
                    self.load { success in
                        DispatchQueue.main.async {
                            self.tableView.reloadData()
                        }
                    }
                    self.signButtonOutlet.setTitle("export", for: .normal)
                }
                
                self.spinner.remove()
                
                showAlert(self, "PSBT signed ✅", "You may now export it by tapping the \"export\" button")
            }
        } else {
            showAlert(self, "Add a psbt first", "You may either tap the paste button, scan a QR or upload a .psbt file.")
        }
    }
    
    private func exportAsFile(_ psbt: Data) {
        guard let url = exportPsbtToURL(data: psbt) else {
            showAlert(self, "Ooops", "We had an issue converting that psbt to raw data.")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView = self.view
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
            }
            
            self.present(activityViewController, animated: true) {}
        }
    }
    
    public func exportPsbtToURL(data: Data) -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let path = documents?.appendingPathComponent("/GordianSigner.psbt") else {
            return nil
        }
        
        do {
            try data.write(to: path, options: .atomicWrite)
            return path
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
        
    private func exportAction() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Export", message: "", preferredStyle: self.alertStyle)
            
            alert.addAction(UIAlertAction(title: ".psbt file", style: .default, handler: { action in
                self.exportAsFile(self.psbt.data)
            }))
            
            alert.addAction(UIAlertAction(title: "psbt base64 text", style: .default, handler: { action in
                self.exportText(self.psbt.description)
            }))
            
            alert.addAction(UIAlertAction(title: "crypto-psbt UR QR", style: .default, handler: { action in
                self.exportAsQR()
            }))
            
            if self.rawTx != "" {
                alert.addAction(UIAlertAction(title: "raw transaction text", style: .default, handler: { action in
                    self.exportText(self.rawTx)
                }))
            }
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true) {}
        }
    }
    
    private func exportAsQR() {
        DispatchQueue.main.async {
            self.performSegue(withIdentifier: "segueToQRDisplayer", sender: self)
        }
    }
    
    private func exportText(_ text: String) {
        DispatchQueue.main.async {
            let textToShare = [text]
            let activityViewController = UIActivityViewController(activityItems: textToShare, applicationActivities: nil)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView = self.view
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
            }
            
            self.present(activityViewController, animated: true) {}
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        if segue.identifier == "segueToQRDisplayer" {
            if let vc = segue.destination as? QRDisplayerViewController {
                vc.text = psbt.description
                vc.isPsbt = true
            }
        }
        
        if segue.identifier == "segueToSign" {
            if let vc = segue.destination as? AddSignerViewController {
                vc.tempWords = true
                
                vc.doneBlock = { [weak self] (arg0) in
                    
                    let (words, passphrase) = arg0
                    guard let self = self else { return }

                    guard let mnemonic = BIP39Mnemonic(words) else { return }

                    let seedHex = mnemonic.seedHex(passphrase)

                    guard let mk = HDKey(seedHex, .testnet) else { return }

                    self.sign(mk)
                }
            }
        }
    }

}