//
//  AddressesViewController.swift
//  GordianSigner
//
//  Created by Peter on 12/10/20.
//  Copyright © 2020 Blockchain Commons. All rights reserved.
//

import UIKit
import LibWally

class AddressesViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var addressesTable: UITableView!
    var addresses = [String]()
    var accountMap:AccountMapStruct!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        addressesTable.delegate = self
        addressesTable.dataSource = self
        load()
    }
    
    private func load() {
        let descriptor = accountMap.descriptor
        let descriptorParser = DescriptorParser()
        let descriptorStruct = descriptorParser.descriptor(descriptor)
        let keys = descriptorStruct.multiSigKeys
        let sigsRequired = descriptorStruct.sigsRequired
        
        for i in 0 ... 999 {
            var pubkeys = [PubKey]()
            var pubkeyStrings = [String]()
            
            for (k, key) in keys.enumerated() {
                let hdKey = try? HDKey(base58: key)
                let path = "0" + "/" + "\(i)"
                
                guard let bip32path = try? BIP32Path(string: path), let key = try? hdKey?.derive(using: bip32path) else {
                    showAlert(self, "", "There was an error deriving your addresses")
                    return
                }
                
                pubkeys.append(key.pubKey)
                pubkeyStrings.append("#\(k + 1): \(key.pubKey.data.hexString)")
                
                if k + 1 == keys.count {
                    let scriptPubKey = ScriptPubKey(multisig: pubkeys, threshold: sigsRequired, isBIP67: true)
                    
                    if let multiSigAddress = try? Address(scriptPubKey: scriptPubKey, network: .mainnet) {
                        addresses.append(multiSigAddress.description)
                    }
                    
                    pubkeys.removeAll()
                }
            }
            
            if i == 999 {
                DispatchQueue.main.async { [weak self] in
                    self?.addressesTable.reloadData()
                }
            }
        }
        
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return addresses.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "addressCell", for: indexPath)
        cell.selectionStyle = .none
        cell.textLabel?.text = "#\(indexPath.row + 1): " + addresses[indexPath.row]
        cell.textLabel?.lineBreakMode = .byCharWrapping
        cell.textLabel?.textColor = .lightGray
        cell.textLabel?.numberOfLines = 0
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
