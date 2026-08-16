---
title: "MIR 3 .5 Mod Portal Upload Checklist"
status: archived
applies_to: "MIR 3 .5 wave"
audience: release-manager
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: []
superseded_by: [docs/releases/mod-portal-page.md]
---

# MIR 3 `.5` Mod Portal upload checklist

No Mod Portal upload has been performed. Upload in this order and use only the exact files listed below.

| Order | Version | Factorio target | Local path | Archive SHA-256 | Content SHA-256 | Bytes | Entries | GitHub tag/release |
| ---: | --- | --- | --- | --- | --- | ---: | ---: | --- |
| 1 | 3.2.5 | 2.1.13 | `dist/more-infinite-research_3.2.5.zip` | `AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF` | `1A2A37380FDE8EA0C260F90414ECB2BF70314341369D816FDD74D59B50535A7D` | 1,056,249 | 301 | [3.2.5](https://github.com/Julesc013/more-infinite-research/releases/tag/3.2.5) |
| 2 | 2.5.5 | 2.0.77 | `dist/more-infinite-research_2.5.5.zip` | `03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C` | `047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154` | 1,055,047 | 300 | [2.5.5](https://github.com/Julesc013/more-infinite-research/releases/tag/2.5.5) |
| 3 | 1.9.5 | 1.1.110 | `dist/more-infinite-research_1.9.5.zip` | `9F044A476500CB72A0C6A9A6254CC702E6621B2CDAEDA04A1188579ADF4AADCC` | `8C8A76EEBFCA52B4A4D401565F08BFD52A285A14837CCC0A65AC689B8F80E9CA` | 397,597 | 174 | [1.9.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.9.5) |
| 4 | 1.8.5 | 1.0.0 only | `dist/more-infinite-research_1.8.5.zip` | `10BA1F1D0EFDED559F447A05164E8865EE35F527C0A7D65D6CB7B1F8C1C4C1CD` | `F950BD20495A00577AA0984300B94F2C01982FE42766BC8906539B509679AB1B` | 397,589 | 174 | [1.8.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.8.5) |
| 5 | 1.7.5 | 0.17.79 | `dist/more-infinite-research_1.7.5.zip` | `D1B3A3348C8A92C29A43C5D0A495686E3ACF21B186BF3DF9D301B63AB0FEDA0A` | `FC636473B31B428C895D14ADB32122235D603CF7ADEC120C50729F572CFD7C2D` | 385,229 | 177 | [1.7.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.7.5) |
| 6 | 1.6.5 | 0.16.51 | `dist/more-infinite-research_1.6.5.zip` | `8EC9E38E091BE82CC4596414C3B6FFDB3E818FEEA4054547C497F7125FCC99CB` | `C19B2F407912E01E12E1D117180504787C352027B9132476A65D9C9D4F4B8392` | 385,236 | 177 | [1.6.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.6.5) |
| 7 | 1.5.5 | 0.15.40 | `dist/more-infinite-research_1.5.5.zip` | `E2060A153B8715755E450AECC825B6C119E2354847D3B041D22DD2E0B5D6FBBD` | `955DF3150304BF6A904E9B90E498F1DDA1D75E433FD1C61D5AD6A4BD139E2778` | 385,548 | 177 | [1.5.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.5.5) |
| 8 | 1.4.5 | 0.14.23 | `dist/more-infinite-research_1.4.5.zip` | `BD866C6D9C13A2ADFB08F7D3EF1D19912FAE3AF2C6BBDE6FEB8A956E3A1BAB47` | `35BB3F593600BC3D5C9D71CEDF502E8480251F6F20C5F5976D91CAE1051145C4` | 385,987 | 177 | [1.4.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.4.5) |
| 9 | 1.3.5 | 0.13.20 | `dist/more-infinite-research_1.3.5.zip` | `78CF6B08E87AC92827926536F3420DDF5695D05E3CA59D83FAF41EBC2E505FB0` | `9E57F57D760D49CF165C66DB3413E2C50D639FA2EC7DB63C44846D001E4EF88A` | 386,081 | 177 | [1.3.5](https://github.com/Julesc013/more-infinite-research/releases/tag/1.3.5) |

After each upload, redownload the Mod Portal asset, verify archive and normalized-content SHA-256 plus bytes and entries, then run the same exact target-engine load check recorded in `MIR-3.5-PUBLIC-ASSET-VERIFICATION.json`. Stop that release on any mismatch. Do not substitute 0.18 for the 1.8.5 Factorio 1.0-only target.
