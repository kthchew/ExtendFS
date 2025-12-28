// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import SwiftUI
import StoreKit

@Observable
class AppStoreRatingManager {
    @ObservationIgnored @AppStorage("lastAskedForRating") var lastAskedForRating: Date = Date.distantPast
    var shouldAskForRatings: Bool {
        let timeSinceLastAskedForRating = lastAskedForRating.timeIntervalSinceNow.magnitude
        let secondsPerMonth = Double(60 * 60 * 24 * 7 * 30)
        
        return !isSignedForDirectDistribution && timeSinceLastAskedForRating > secondsPerMonth
    }
    
    private let requestRatingAction: RequestReviewAction
    private let isSignedForDirectDistribution: Bool
    
    static fileprivate func checkIfDirectDistributionSigned() -> Bool {
        var code: SecCode? = nil
        SecCodeCopySelf(SecCSFlags(), &code)
        guard let code else { return true }
        var staticCode: SecStaticCode? = nil
        SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard let staticCode else { return true }
        var dict: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &dict)
        guard let info = dict as? [CFString: Any], let certificates = info[kSecCodeInfoCertificates] as? [SecCertificate] else {
            return true
        }
        return certificates.contains { cert in
            var commonName: CFString? = nil
            SecCertificateCopyCommonName(cert, &commonName)
            guard let commonName = commonName as? String else { return false }
            return commonName.contains("Developer ID Application")
        }
    }
    
    init(action: RequestReviewAction) {
        self.requestRatingAction = action
        
        self.isSignedForDirectDistribution = Self.checkIfDirectDistributionSigned()
    }
    
    @MainActor func requestRating() {
        lastAskedForRating = Date.now
        self.requestRatingAction()
    }
}
