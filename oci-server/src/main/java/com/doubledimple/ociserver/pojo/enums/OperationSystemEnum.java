package com.doubledimple.ociserver.pojo.enums;

public enum OperationSystemEnum {
    /** 
    * [
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-9.4-Minimal-2024.09.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaltnxteh7x6efur2n5okiaesg5h6otfmfv6x73wnxha2qdxplgp2q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "9 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2024-10-12T04:35:42.131Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-aarch64-2025.09.16-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa4mcklopjv3g2g36qoqiz2k5wal76fum2uevttyuvadjmeqf24pja",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-24T04:10:00.734Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-aarch64-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaavhg5bph6nkhgfadebbadwfiw5q6cqsp32zzuc2n3cziemqdgcipa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-03T04:03:06.617Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-aarch64-2025.07.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaakhrhl2hqkjfryj4nqa4dahwa5pjopovsudkalqf4jce5yjocx64q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-08-26T03:30:37.445Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-Gen2-GPU-2025.09.16-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaduhmocm6hqbot7yrxbqxd6ymepjbi42xbz55kxbo3dpdtlxjdmwa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 17,
     *         "timeCreated": "2025-09-24T04:10:22.213Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-Gen2-GPU-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaay2amhvu3y2zkdk3slng6ns5ihen62f6oqlhwjjuwxbbzxfiksl2a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 19,
     *         "timeCreated": "2025-09-03T04:03:51.632Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-Gen2-GPU-2025.07.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaavsqxgws7wdq25szmlojo2sonq44xmufcondx5jbesklt7rsrnwq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 19,
     *         "timeCreated": "2025-08-26T03:31:26.467Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-Gen2-AMD-GPU-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaxfnmdaqmnuwmmc3yuvbuconce5itka7ikrocxmpfvy4qrfqcrrga",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 26,
     *         "timeCreated": "2025-10-08T20:49:01.496Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-Gen2-AMD-GPU-2024.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaanuzh5s4zmvrdq3ckm6e57tp6gvsciwkw2u7vxepo2c3n5c5p4wcq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 153600,
     *         "billableSizeInGBs": 34,
     *         "timeCreated": "2024-10-12T04:34:21.740Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-2025.09.16-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaa6lrnxtr5q3r73nqq5n57ubpnlh7kgr3ombrrijkkf5qji2d4eqq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-24T04:10:29.879Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaalwgijxg2pvw66vin63b7jsctc32iuefjr6msb66wuw4zvtamxxva",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-03T04:03:45.997Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-8.10-2025.07.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaamyfeo5qx6rwjc2kcmhoamvieh37latxk4ajteorux36fqpvfkmpa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-08-26T03:30:42.129Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-aarch64-2024.11.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaairfjls6x4yx7egfutigrgdipuqliffnocqffwj23hiiagfex6mla",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-01-15T05:30:40.582Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-aarch64-2024.10.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaczbkoarvfdw6enrwkx6i4of7k5u6oinedrrzreq72ah45thofxuq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2024-12-11T05:08:42.659Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-aarch64-2024.09.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaag42b27mhsdbnmsa7buyrjch7n5ka36m7itw57oohxe4nsge2aswa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2024-10-12T04:34:01.927Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-Gen2-GPU-2025.07.21-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaavp7nlkghrboixlcbwwiaotltagcnwq4n5555p65p3gkbqph3z5a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 15,
     *         "timeCreated": "2025-07-25T07:01:35.832Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-Gen2-GPU-2025.01.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaulfq6hxjhqbsd5t7dv23czq74iduwx4souh5tildh2pzxym43udq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 15,
     *         "timeCreated": "2025-02-13T08:54:43.553Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-Gen2-GPU-2024.11.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaal4g4nfforng2uc2esogo54wvr7sm3cd66eqhex7z7skxo3ahrqla",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 15,
     *         "timeCreated": "2025-01-15T05:29:57.695Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-2025.07.21-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaxralxkbgt7ro2xsbpebcovyrrm4yfxazgpjwfh37hvqxmvpemsaa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 5,
     *         "timeCreated": "2025-07-25T07:01:13.655Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-2025.04.16-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaiscyshxg4tsrlk4trmj3tvk36drfsw6bnfft72rkusw3dwa2qdxa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 5,
     *         "timeCreated": "2025-04-24T06:39:38.252Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-7.9-2025.01.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaqhduu7nfiykttv3xkfb5wopizfjhw4zionfbkcm5cvwv6lmge56q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 5,
     *         "timeCreated": "2025-02-13T08:52:24.010Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-6.10-2022.02.13-1",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa44uhbfkdvkircsw4owvbtyzgx3brdjclwzp4ucieoar2t4bydieq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "6.10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2022-03-17T21:36:20.282Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-6.10-2021.03.17-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa5rcwolpg465aj35zt4bkgg4gcujcto7gvfz6wajk53fnpysbaxea",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "6.10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 0,
     *         "timeCreated": "2021-03-24T02:48:24.558Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-10.0-aarch64-2025.09.16-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaadodgh4bvvcbm77tkhwkyd6saditaed2ttt46tsljtszfpn5otsia",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-09-24T04:13:32.237Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-10.0-aarch64-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaeputur7q2mlndyzilimwnilcn5sofy4uqgx7j2ndb7kknvibxoaq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-09-03T04:08:33.931Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-10.0-aarch64-2025.07.31-2",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa2hb4fk6rkht2p53tve4dows2cucqgqzyaffeffytfxtrrgsw22ia",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-08-26T02:58:57.193Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-10.0-2025.09.16-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaanhcwqc4yiy57tkdqq4sfu6q2hjk33vg66d6x2tznwikhh63imjq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-09-24T04:13:04.424Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-10.0-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaftga32kvnz2vqqme3mlkc7gbjkfrdfsr6sdgdiiibujhysvxycsq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-09-03T04:07:38.848Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Linux-10.0-2025.07.31-2",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaux5sayve2445s7j7ozuagp4z4qfpckw3xtheigj4uifequg5c2ya",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Linux",
     *         "operatingSystemVersion": "10",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2025-08-26T02:58:36.511Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-9.6-2025.09.18-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaapgknn4klvghyzcmky6ip7tpc2cmqskxjfrrzgunzhhs5l2pr33nq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-26T02:34:03.636Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-9.6-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaapvdbmqxmwvk5iymp5c2hgxczyiykbaswqpixjergdnfubrsl7ugq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-08T06:07:20.362Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-9.6-2025.07.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaqenge2pe7ynf4b6ubpfh6m7tzx4f2t6b4txno5ytlwswlanona7q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-08-19T05:40:16.073Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-8.10-2025.09.18-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaahevyabvv3uigjirthbi5ilf6bc3dobjq3564jrtkblmyerpvdwq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-26T02:33:59.750Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-8.10-2025.08.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaukzfliosyxohi5rnqeubxkvgi3j5lainhug6wmbqf4xzcvosi4za",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-09-08T06:06:59.810Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-8.10-2025.06.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa7i633xfyye23htxftvklju7dvplvngwizekmnw32e73jxjvnwjja",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "8",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47719,
     *         "billableSizeInGBs": 6,
     *         "timeCreated": "2025-08-01T06:47:09.248Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-7.9-2025.04.21-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaamcsfcn7qjck4q2gcvkq3miivb43y3nu74quxb2ugnw4p4hb52nwq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 5,
     *         "timeCreated": "2025-04-24T06:39:37.934Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-7.9-2025.01.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaiksv435evtgr6tbo66g6flmapqe2juetif3445a7yzixsylivk6a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 5,
     *         "timeCreated": "2025-02-16T10:00:56.068Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Oracle-Autonomous-Linux-7.9-2024.11.30-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaannxpggul5ljymi2n575dowk7y2gq6kfhm3gu7mkkffnirmj7rriq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Oracle Autonomous Linux",
     *         "operatingSystemVersion": "7.9",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 5,
     *         "timeCreated": "2025-01-28T05:19:34.726Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "CentOS-8-Stream-2024.04.25-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaul3ds7anoxbgr7b7jclvjetbo3nwueibpawh3fxo4u4jqjrxgefa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "CentOS",
     *         "operatingSystemVersion": "8 Stream",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2024-05-10T07:01:00.780Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "CentOS-8-Stream-2024.03.19-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaalaosgbbaute5vt7d56ev3ponfljhlfjghpqbklluu7zsz6boyqga",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "CentOS",
     *         "operatingSystemVersion": "8 Stream",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2024-04-30T07:18:53.310Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "CentOS-8-Stream-2024.02.26-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaarufxudlct6cxblzhtfdcmn25hseolevbtucwylust4ekvag65gxq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "CentOS",
     *         "operatingSystemVersion": "8 Stream",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 4,
     *         "timeCreated": "2024-03-07T06:08:25.886Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "CentOS-7-2024.05.31-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaadrgwq2hantofb6ysa35k3lklot4dpehnl5esyxzdn27he76lipfa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "CentOS",
     *         "operatingSystemVersion": "7",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2024-07-16T09:16:42.307Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "CentOS-7-2024.04.25-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaae5y3zaeq6iqmgdwxgww3euvshyp7k3go3qhe6zmy5bzvhx2requa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "CentOS",
     *         "operatingSystemVersion": "7",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2024-05-10T07:01:33.659Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "CentOS-7-2024.03.19-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaaedlgf3rzo4msclddrryl7t4nn2gt5sfcapo36ukofz2ozchdysq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "CentOS",
     *         "operatingSystemVersion": "7",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2024-04-30T07:18:45.762Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-aarch64-2025.09.26-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaagmheotcqrduf2woaj6a3d6pgubqyklrrzk5igmwaqxlg57hruksa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-10-02T14:00:25.082Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-aarch64-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaqycayw3piwmbngunrfijh3b4fikfbb6rd4jfjcvslugisbjnck6a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:19:02.215Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-aarch64-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaarcbc3y6yx6nmsu5rfipwz362oiex4xv2ullte7leheohvxam5kpa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-05-22T02:03:06.779Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-Minimal-aarch64-2025.09.22-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaae2z2lh5w2oc6hw67tgl3azrlhcfhipjqtxpt264gtdlyaxc6vaaq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04 Minimal aarch64",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-10-02T13:59:15.266Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-Minimal-aarch64-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaawkxvz7hvgqvq3moezgkhvhv54uifi3jr46ogxr4u345xyfpglorq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04 Minimal aarch64",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:16:37.298Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-Minimal-aarch64-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaagv4sgoph76vx6umntk73shyufi5z3m7uv4oy6cwggxp37krptozq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04 Minimal aarch64",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 1,
     *         "timeCreated": "2025-05-22T02:01:14.899Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-Minimal-2025.09.22-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaalcd7oym4puu7y4i4b5ccfqpnkohy4sig7u2ctbynmdyvkuuoio7a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-10-02T13:59:26.991Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-Minimal-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa7swlmrjwd4wb4ssuho7rsmel7dmobrdycwhhch3eeqtcjdk5i63a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:13:32.495Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-Minimal-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaazcgq6ivobkg4mkuqqs7pngp3hz4bmpf2da77p5e3t7xltely4o2q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-05-22T02:02:54.628Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-2025.09.22-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaakmmhmdqdhtivmcvk3xddjc7ubjx6wz5qm7crbqw4cukdjohkcela",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-10-02T14:00:19.588Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaablxvx3zzd64m4gdcemyddapx5sc7nt7v77oksprbw44loroywukq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-08-01T09:11:45.479Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-24.04-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaavlpts7ysq2avsu5ysulvfkwzyorbzmyhqnyoggansikwndi23njq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "24.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-05-22T02:01:56.136Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-aarch64-2025.09.26-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaalse4yqbg7hi7aydl6yn6vxx3g6otxoor7qg2wqjyb4pgrwku63ta",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-10-02T13:59:06.427Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-aarch64-2025.07.24-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaahd4gfraumftpq3qgghwdz2anq4drmntq45hbacbawf4fhymrejmq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:08:54.414Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-aarch64-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaf76levgnehn575o5vcjf4trqmvkqft2dzg6rrmwvblmnuxoewz4a",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-05-22T02:01:35.572Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-Minimal-aarch64-2025.09.22-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaawhx63mlxuytu5z4nrxhopnwkxx3f6pcurkwubly3cyawvm3raica",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04 Minimal aarch64",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-10-02T13:59:42.275Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-Minimal-aarch64-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa5ert6nzvwkfwu3ai357s7n26bxnrq4dpfctynfrqiybsz42ulsiq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04 Minimal aarch64",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:11:46.353Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-Minimal-aarch64-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaafwwhmcics4s2zdvgxj2qvpiadvinlnsn75ijlwp37kjeqiets7q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04 Minimal aarch64",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-05-22T02:01:47.292Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-Minimal-2025.09.22-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaagmekbsgk6pvvm5amhcbtjbfkawabq36jwur2yievxwrlbh52xeia",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-10-02T13:58:53.215Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-Minimal-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaadomp3v7hsn62vu33vnww2mnoakrty6fgm2r7jgo3jseumw7rmrba",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:07:56.414Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-Minimal-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaypn6inf66chyezjjyqsu4tqy4o7dofexdy7hnozmww6nmpxmkyhq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-05-22T01:13:01.992Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-2025.09.22-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaalngjz6dogvufpouxdurtaenmasrfjnmh7ynvpondf2fzlgcnixoq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-10-02T13:58:46.188Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaae2nv7yctlzcirczuz5qjuw3vzjjkifhhce4ol5xirgkxnodmq2pa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-08-01T09:06:01.225Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-22.04-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaav54pq3qzx366zjxbmnqcag2vol43wjeayu6pesy4m6v3hu2dgi4q",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "22.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-05-22T01:59:38.988Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-aarch64-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaxm3rh4iugzlpbeq4e64vjvyyq2lhq25psfmoinivahrmdd3ao2sa",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-08-01T09:05:59.404Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-aarch64-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaawydlorprhl7k5atoy2yczqb4irmh35346ey7hv7ty5x4bepfi4ea",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-05-22T02:02:50.229Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-aarch64-2025.03.28-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaiehrnjpr75zj4pmfmcllf774q2jwasyujx4wimgygvd3j6plfqgq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-03-30T16:50:22.248Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-Minimal-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaal437z2ekghw3dtrnovcgf2tbqlibkc2xrqnqflndlopmtypljrsq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-08-01T09:04:47.996Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-Minimal-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaaxykqisio4yqa5h33nzxzarcccporphkyi5khpocpazldotns6iya",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-05-22T01:59:11.626Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-Minimal-2025.03.28-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaawxmnzuuher4go3mzsapvuzk56a5xgvkglnnrefar3demy252inrq",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04 Minimal",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 2,
     *         "timeCreated": "2025-03-30T16:50:13.623Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-2025.07.23-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaa3eoeyy4p5pmdwnmkvre6vw5ng3rsp6i6t7uhmu24reuuxvb5scva",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-08-01T09:05:37.685Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-2025.05.20-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaasgykideyv6yxukev4og6v4qdjpo2x52qku6xjxaioclrr6v4zpva",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-05-22T02:02:11.467Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     },
     *     {
     *         "baseImageId": null,
     *         "compartmentId": null,
     *         "createImageAllowed": true,
     *         "definedTags": {},
     *         "displayName": "Canonical-Ubuntu-20.04-2025.03.28-0",
     *         "freeformTags": {},
     *         "id": "ocid1.image.oc1.ap-sydney-1.aaaaaaaahobkratzqhtbbt4r3dsogjqkslqvcsyh5v4sgxgcib7kuj3rpgma",
     *         "launchMode": "NATIVE",
     *         "launchOptions": {
     *             "bootVolumeType": "PARAVIRTUALIZED",
     *             "firmware": "UEFI_64",
     *             "networkType": "PARAVIRTUALIZED",
     *             "remoteDataVolumeType": "PARAVIRTUALIZED",
     *             "isPvEncryptionInTransitEnabled": true,
     *             "isEncryptionInTransitEnabled": null,
     *             "isConsistentVolumeNamingEnabled": true
     *         },
     *         "lifecycleState": "AVAILABLE",
     *         "operatingSystem": "Canonical Ubuntu",
     *         "operatingSystemVersion": "20.04",
     *         "agentFeatures": null,
     *         "listingType": null,
     *         "sizeInMBs": 47694,
     *         "billableSizeInGBs": 3,
     *         "timeCreated": "2025-03-30T16:13:08.764Z",
     *         "imageVolumeDetails": {
     *             "dataVolumes": []
     *         }
     *     }
     * ]
    */


    ORACLE_LINUX("Oracle Autonomous Linux","9"),

    UBUNTU_20_04("Canonical Ubuntu","20.04"),
    UBUNTU_20_04_MINIMAL("Canonical Ubuntu","20.04 Minimal"),
    UBUNTU_22_04("Canonical Ubuntu","22.04"),
    UBUNTU_22_04_MINIMAL("Canonical Ubuntu","22.04 Minimal"),
    UBUNTU_22_04_MINIMAL_AARCH64("Canonical Ubuntu","22.04 Minimal aarch64"),
    UBUNTU_24_04("Canonical Ubuntu","24.04"),

    CENT_OS_7("CentOS","7"),
    CENT_OS_8_STREAM("CentOS","8 Stream"),


    ;

    OperationSystemEnum(String type,String version){

        this.type = type;
        this.version = version;
    }
    private String type;
    private String version;


    public String getType(){
        return type;
    }
    public String getVersion(){
        return version;
    }


    public static  OperationSystemEnum getSystemType(String type){
        OperationSystemEnum[] values = OperationSystemEnum.values();
        for (OperationSystemEnum value : values) {
            if (value.getType().equals(type)){
                if (value.getType().equals("Canonical Ubuntu")){
                    return OperationSystemEnum.UBUNTU_20_04;
                }else{
                    return value;
                }
            }
        }
        return OperationSystemEnum.UBUNTU_20_04;
    }


    public static  OperationSystemEnum getDefaultSystemType(){
        return OperationSystemEnum.UBUNTU_20_04;
    }

}
