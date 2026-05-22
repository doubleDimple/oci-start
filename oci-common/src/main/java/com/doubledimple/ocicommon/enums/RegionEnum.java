package com.doubledimple.ocicommon.enums;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public enum RegionEnum {

    AF_JOHANNESBURG_1("af-johannesburg-1", "中东非洲-南非中部约翰内斯堡","约翰内斯堡", "https://objectstorage.af-johannesburg-1.oraclecloud.com", "za"),
    AF_CASABLANCA_1("af-casablanca-1", "中东非洲-摩洛哥卡萨布兰卡", "卡萨布兰卡", "https://objectstorage.af-casablanca-1.oraclecloud.com", "ma"),
    AP_CHUNCHEON_1("ap-chuncheon-1", "亚太-韩国北部春川","春川", "https://objectstorage.ap-chuncheon-1.oraclecloud.com", "kr"),
    AP_HYDERABAD_1("ap-hyderabad-1", "亚太-印度南部海得拉巴","海得拉巴", "https://objectstorage.ap-hyderabad-1.oraclecloud.com", "in"),
    AP_MELBOURNE_1("ap-melbourne-1", "亚太-澳大利亚东南部墨尔本","墨尔本", "https://objectstorage.ap-melbourne-1.oraclecloud.com", "au"),
    AP_MUMBAI_1("ap-mumbai-1", "亚太-印度西部孟买","孟买", "https://objectstorage.ap-mumbai-1.oraclecloud.com", "in"),
    AP_OSAKA_1("ap-osaka-1", "亚太-日本中部大阪","大阪", "https://objectstorage.ap-osaka-1.oraclecloud.com", "jp"),
    AP_SEOUL_1("ap-seoul-1", "亚太-韩国中部首尔","首尔", "https://objectstorage.ap-seoul-1.oraclecloud.com", "kr"),
    AP_KULAI_2("ap-kulai-2", "亚太-马来西亚古来","古来", "https://objectstorage.ap-kulai-2.oraclecloud.com", "my"),
    AP_SINGAPORE_1("ap-singapore-1", "亚太-新加坡","新加坡", "https://objectstorage.ap-singapore-1.oraclecloud.com", "sg"),
    AP_BATAM_1("ap-batam-1", "亚太-印度尼西亚巴淡","巴淡", "https://objectstorage.ap-batam-1.oraclecloud.com", "id"),
    AP_SINGAPORE_2("ap-singapore-2", "亚太-新加坡西","新加坡西", "https://objectstorage.ap-singapore-2.oraclecloud.com", "sg"),
    AP_SYDNEY_1("ap-sydney-1", "亚太-澳大利亚东部悉尼","悉尼", "https://objectstorage.ap-sydney-1.oraclecloud.com", "au"),
    AP_TOKYO_1("ap-tokyo-1", "亚太-日本东部东京","东京", "https://objectstorage.ap-tokyo-1.oraclecloud.com", "jp"),
    CA_MONTREAL_1("ca-montreal-1", "北美-加拿大东南部蒙特利尔","蒙特利尔", "https://objectstorage.ca-montreal-1.oraclecloud.com", "ca"),
    CA_TORONTO_1("ca-toronto-1", "北美-加拿大东南部多伦多","多伦多", "https://objectstorage.ca-toronto-1.oraclecloud.com", "ca"),
    EU_AMSTERDAM_1("eu-amsterdam-1", "欧洲-荷兰西北部阿姆斯特丹","阿姆斯特丹", "https://objectstorage.eu-amsterdam-1.oraclecloud.com", "nl"),
    EU_FRANKFURT_1("eu-frankfurt-1", "欧洲-德国中部法兰克福","法兰克福", "https://objectstorage.eu-frankfurt-1.oraclecloud.com", "de"),
    EU_JOVANOVAC_1("eu-jovanovac-1", "欧洲-塞尔维亚中部乔万诺瓦茨","乔万诺瓦茨", "https://objectstorage.eu-jovanovac-1.oraclecloud.com", "rs"),
    EU_MADRID_1("eu-madrid-1", "欧洲-西班牙中部马德里-1","马德里-1", "https://objectstorage.eu-madrid-1.oraclecloud.com", "es"),
    EU_MADRID_3("eu-madrid-3", "欧洲-西班牙中部马德里-3","马德里-3", "https://objectstorage.eu-madrid-3.oraclecloud.com", "es"),
    EU_MARSEILLE_1("eu-marseille-1", "欧洲-法国南部马赛","马赛", "https://objectstorage.eu-marseille-1.oraclecloud.com", "fr"),
    EU_MILAN_1("eu-milan-1", "欧洲-意大利西北部米兰","米兰", "https://objectstorage.eu-milan-1.oraclecloud.com", "it"),
    EU_TURIN_1("eu-turin-1", "欧洲-意大利西北部都灵","都灵", "https://objectstorage.eu-turin-1.oraclecloud.com", "it"),
    EU_PARIS_1("eu-paris-1", "欧洲-法国中部巴黎","巴黎", "https://objectstorage.eu-paris-1.oraclecloud.com", "fr"),
    EU_STOCKHOLM_1("eu-stockholm-1", "欧洲-瑞典中部斯德哥尔摩","斯德哥尔摩", "https://objectstorage.eu-stockholm-1.oraclecloud.com", "se"),
    EU_ZURICH_1("eu-zurich-1", "欧洲-瑞士北部苏黎世","苏黎世", "https://objectstorage.eu-zurich-1.oraclecloud.com", "ch"),
    IL_JERUSALEM_1("il-jerusalem-1", "欧洲-以色列中部耶路撒冷","耶路撒冷", "https://objectstorage.il-jerusalem-1.oraclecloud.com", "il"),
    ME_ABUDHABI_1("me-abudhabi-1", "中东-阿联酋阿布扎比","阿布扎比", "https://objectstorage.me-abudhabi-1.oraclecloud.com", "ae"),
    ME_DUBAI_1("me-dubai-1", "中东-阿联酋迪拜","迪拜", "https://objectstorage.me-dubai-1.oraclecloud.com", "ae"),
    ME_JEDDAH_1("me-jeddah-1", "中东-沙特阿拉伯西部吉达","吉达", "https://objectstorage.me-jeddah-1.oraclecloud.com", "sa"),
    ME_RIVADH_1("me-riyadh-1", "中东-沙特阿拉伯首都利雅得","利雅得", "https://objectstorage.me-riyadh-1.oraclecloud.com", "sa"),
    MX_MONTERREY_1("mx-monterrey-1", "北美-墨西哥东北部蒙特雷","蒙特雷", "https://objectstorage.mx-monterrey-1.oraclecloud.com", "mx"),
    MX_QUERETARO_1("mx-queretaro-1", "北美-墨西哥中部克雷塔罗","克雷塔罗", "https://objectstorage.mx-queretaro-1.oraclecloud.com", "mx"),
    SA_BOGOTA_1("sa-bogota-1", "南美-哥伦比亚中部波哥大","波哥大", "https://objectstorage.sa-bogota-1.oraclecloud.com", "co"),
    SA_SANTIAGO_1("sa-santiago-1", "南美-智利中部圣地亚哥","圣地亚哥", "https://objectstorage.sa-santiago-1.oraclecloud.com", "cl"),
    SA_SAOPAULO_1("sa-saopaulo-1", "南美-巴西东部圣保罗","圣保罗", "https://objectstorage.sa-saopaulo-1.oraclecloud.com", "br"),
    SA_VINHEDO_1("sa-vinhedo-1", "南美-巴西南部维涅杜","维涅杜", "https://objectstorage.sa-vinhedo-1.oraclecloud.com", "br"),
    UK_CARDIFF_1("uk-cardiff-1", "欧洲-英国西部加的夫","加的夫", "https://objectstorage.uk-cardiff-1.oraclecloud.com", "gb"),
    UK_LONDON_1("uk-london-1", "欧洲-英国南部伦敦","伦敦", "https://objectstorage.uk-london-1.oraclecloud.com", "gb"),
    US_ASHBURN_1("us-ashburn-1", "北美-美国东部阿什本","阿什本", "https://objectstorage.us-ashburn-1.oraclecloud.com", "us"),
    US_CHICAGO_1("us-chicago-1", "北美-美国中西部芝加哥","芝加哥", "https://objectstorage.us-chicago-1.oraclecloud.com", "us"),
    US_PHOENIX_1("us-phoenix-1", "北美-美国西部凤凰城","凤凰城", "https://objectstorage.us-phoenix-1.oraclecloud.com", "us"),
    US_SANJOSE_1("us-sanjose-1", "北美-美国西部圣何塞","圣何塞", "https://objectstorage.us-sanjose-1.oraclecloud.com", "us"),
    SA_VALPARAISO_1("sa-valparaiso-1", "南美-智利西部瓦尔帕莱索","瓦尔帕莱索", "https://objectstorage.sa-valparaiso-1.oraclecloud.com",  "cl"),

    GCP_REGION("gcp-region", "美国","美国","","us"),

    ;

    private final String code;
    private final String name;

    private final String simpleName;

    private final String endpoint;

    private final String flagCode;

    RegionEnum(String code, String name, String simpleName, String endpoint, String flagCode) {
        this.code = code;
        this.name = name;
        this.simpleName = simpleName;
        this.endpoint = endpoint;
        this.flagCode = flagCode;
    }

    public String getCode() {
        return code;
    }

    public String getName() {
        return name;
    }

    public String getSimpleName() {
        return simpleName;
    }

    public String getEndpoint() {
        return endpoint;
    }

    public String getFlagCode() {
        return flagCode;
    }

    public static String getNameByCode(String code) {
        if (containsChineseByRegex(code)){
            for (RegionEnum region : RegionEnum.values()) {
                if (region.name.equals(code)) {
                    return region.getSimpleName();
                }
            }
            return code;
        }else {
            for (RegionEnum region : RegionEnum.values()) {
                if (region.code.equals(code)) {
                    return region.getSimpleName();
                }
            }
            return code;
        }
    }

    public static String getCodeByName(String name) {
        for (RegionEnum region : RegionEnum.values()) {
            if (region.name.equals(name) || region.simpleName.equals(name)) {
                return region.getCode();
            }
        }

        for (RegionEnum region : RegionEnum.values()) {
            if (region.code.equals(name)) {
                return region.getCode();
            }
        }
        return name;
    }

    public static boolean containsChineseByRegex(String str) {
        return str != null && str.matches(".*[\\u4e00-\\u9fa5]+.*");
    }


    public static String getNameCh(String code){
        if (containsChineseByRegex(code)){
            return code;
        }else {
            for (RegionEnum region : RegionEnum.values()) {
                if (region.code.equals(code)) {
                    return region.getName();
                }
            }
            return code;
        }
    }

    public static String getNameSimple(String code){
        if (containsChineseByRegex(code)){
            for (RegionEnum region : RegionEnum.values()) {
                if (region.name.equals(code)) {
                    return region.getSimpleName();
                }
            }
            return code;
        }else {
            for (RegionEnum region : RegionEnum.values()) {
                if (region.code.equals(code)) {
                    return region.getSimpleName();
                }
            }
            return code;
        }
    }

    public static List<String> getRegions(String code) {
        List<String> regions = new ArrayList<>();
        if (containsChineseByRegex(code)) {
            // 如果输入是中文，添加中文并查找对应的英文code
            regions.add(code);
            for (RegionEnum region : RegionEnum.values()) {
                if (region.getName().equals(code)) {
                    regions.add(region.code);
                    break;
                }
            }
        } else {
            // 如果输入是英文code，添加code并查找对应的中文名
            regions.add(code);
            for (RegionEnum region : RegionEnum.values()) {
                if (region.code.equals(code)) {
                    regions.add(region.getName());
                    break;
                }
            }
        }

        return regions;
    }

    /**
     * 获取区域代码
     * 如果输入的是中文区域名称，则返回对应的英文区域代码
     * 如果输入的是英文区域代码，则直接返回该代码
     *
     * @param regionInput 区域输入（可以是中文名称或英文代码）
     * @return 区域代码
     */
    public static String getRegionCode(String regionInput) {
        if (regionInput == null || regionInput.trim().isEmpty()) {
            return null;
        }

        // 判断是否包含中文
        if (containsChineseByRegex(regionInput)) {
            // 输入是中文，查找对应的英文代码
            for (RegionEnum region : RegionEnum.values()) {
                if (region.getName().equals(regionInput) || region.getSimpleName().equals(regionInput)) {
                    return region.getCode();
                }
            }
            return regionInput;
        } else {
            return regionInput;
        }
    }

    public static List<String> getNotSupportHelp() {

        return Arrays.asList(
                EU_JOVANOVAC_1.getCode(),
                MX_MONTERREY_1.getCode(),
                SA_BOGOTA_1.getCode(),
                US_CHICAGO_1.getCode(),
                SA_VALPARAISO_1.getCode(),
                AP_SINGAPORE_1.getCode(),
                AP_SINGAPORE_2.getCode(),
                ME_RIVADH_1.getCode(),
                AP_BATAM_1.getCode(),
                EU_MADRID_1.getCode()
                );
    }


    public static List<String> getSupportAiRegion() {

        return Arrays.asList(
                US_ASHBURN_1.getCode(),
                US_CHICAGO_1.getCode(),
                US_PHOENIX_1.getCode(),
                AP_OSAKA_1.getCode()
        );
    }

    //获取所有数据
    public static List<Map<String, Object>> getAllRegion() {
        List<Map<String, Object>> list = new ArrayList<>();
        for (RegionEnum r : RegionEnum.values()) {
            if (r.getEndpoint() != null && !r.getEndpoint().isEmpty()) {
                Map<String, Object> map = new HashMap<>();
                map.put("code", r.getCode());
                map.put("name", r.getName());
                map.put("simpleName", r.getSimpleName());
                map.put("endpoint", r.getEndpoint());
                list.add(map);
            }
        }
        return list;
    }

    public String getFlagUrlBase() {
        String fCode = (this.flagCode == null || this.flagCode.isEmpty()) ? "xx" : this.flagCode;
        return "/images/flags/" + fCode + ".svg";
    }

    public static String getFlagUrl(String regionInput) {
        String baseFlag = "/images/flags/";
        String defaultFlag = baseFlag + "xx.svg";
        if (regionInput == null || regionInput.trim().isEmpty()) {
            return defaultFlag;
        }
        RegionEnum targetRegion = null;
        if (containsChineseByRegex(regionInput)) {
            for (RegionEnum region : RegionEnum.values()) {
                if (region.getName().equals(regionInput)) {
                    targetRegion = region;
                    break;
                }
            }
        } else {
            for (RegionEnum region : RegionEnum.values()) {
                if (region.getCode().equalsIgnoreCase(regionInput)) {
                    targetRegion = region;
                    break;
                }
            }
        }
        if (targetRegion != null) {
            String fCode = targetRegion.getFlagCode();
            if (fCode != null && !fCode.isEmpty()) {
                return baseFlag + fCode + ".svg";
            }
        }
        return defaultFlag;
    }
}
