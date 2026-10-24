/*
 * Login map catalogue, checked against Oracle documentation on 2026-09-15.
 * Scope: all 45 entries in Oracle's commercial-region table (44 OC1 + 1 OC20).
 * This is not a catalogue of government, sovereign, dedicated, Alloy, or
 * multicloud deployments, nor a promise that one tenancy can use every region.
 * Region identifiers and published locations:
 * https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm
 *
 * Coordinates represent the published city/locality, NOT an availability
 * domain or an exact data-centre location. Oracle's table does not publish
 * precise facility coordinates. Most representative points are reused from
 * oci-start-web/src/views/regions/regionCoords.ts; their decimal precision must
 * not be interpreted as surveyed facility accuracy.
 *
 * Corrections to that legacy coordinate catalogue:
 * - uk-cardiff-1 is Newport, as named in Oracle's table, rather than Cardiff.
 *   GeoNames Newport (2641598), rounded to four decimal places:
 *   https://www.geonames.org/search.html?q=Newport
 *   https://digital.library.unt.edu/explore/locations/p17610/
 * - eu-jovanovac-1 uses the populated locality Jovanovac in Kragujevac,
 *   rounded from GeoNames 44.050061, 20.950654, rather than the old remote point.
 *   Oracle identifies this region with Kragujevac:
 *   https://docs.oracle.com/en/solutions/oci-serbia-realm/index.html
 *   GeoNames locality record in its Serbia gazetteer (entry 2726):
 *   https://www.geonames.org/advanced-search.html?country=RS&featureClass=P&q=&startRow=2700
 * - Both Singapore regions share Singapore's representative point. Both
 *   Madrid regions likewise share Madrid's point. Do not offset coordinates
 *   to separate pins: the map and directory must preserve both region codes.
 *
 * GeoNames geographical data attribution: https://www.geonames.org/
 * This static catalogue makes no requests and contains no tenancy information.
 */
export default {
  checkedAt: '2026-09-15',
  scope: 'oci-public-commercial-regions',
  regions: [
    { code: 'ap-sydney-1', zh: '悉尼', en: 'Sydney', lat: -33.8688, lng: 151.2093 },
    { code: 'ap-melbourne-1', zh: '墨尔本', en: 'Melbourne', lat: -37.8136, lng: 144.9631 },
    { code: 'sa-saopaulo-1', zh: '圣保罗', en: 'São Paulo', lat: -23.5505, lng: -46.6333 },
    { code: 'sa-vinhedo-1', zh: '维涅杜', en: 'Vinhedo', lat: -23.0304, lng: -46.9834 },
    { code: 'ca-montreal-1', zh: '蒙特利尔', en: 'Montréal', lat: 45.5017, lng: -73.5673 },
    { code: 'ca-toronto-1', zh: '多伦多', en: 'Toronto', lat: 43.6532, lng: -79.3832 },
    { code: 'sa-santiago-1', zh: '圣地亚哥', en: 'Santiago', lat: -33.4489, lng: -70.6693 },
    { code: 'sa-valparaiso-1', zh: '瓦尔帕莱索', en: 'Valparaíso', lat: -33.0472, lng: -71.6127 },
    { code: 'sa-bogota-1', zh: '波哥大', en: 'Bogotá', lat: 4.711, lng: -74.0721 },
    { code: 'eu-paris-1', zh: '巴黎', en: 'Paris', lat: 48.8566, lng: 2.3522 },
    { code: 'eu-marseille-1', zh: '马赛', en: 'Marseille', lat: 43.2965, lng: 5.3698 },
    { code: 'eu-frankfurt-1', zh: '法兰克福', en: 'Frankfurt', lat: 50.1109, lng: 8.6821 },
    { code: 'ap-hyderabad-1', zh: '海得拉巴', en: 'Hyderabad', lat: 17.385, lng: 78.4867 },
    { code: 'ap-mumbai-1', zh: '孟买', en: 'Mumbai', lat: 19.076, lng: 72.8777 },
    { code: 'ap-batam-1', zh: '巴淡', en: 'Batam', lat: 1.1074, lng: 104.03 },
    { code: 'il-jerusalem-1', zh: '耶路撒冷', en: 'Jerusalem', lat: 31.7683, lng: 35.2137 },
    { code: 'eu-milan-1', zh: '米兰', en: 'Milan', lat: 45.4642, lng: 9.19 },
    { code: 'eu-turin-1', zh: '都灵', en: 'Turin', lat: 45.0703, lng: 7.6869 },
    { code: 'ap-osaka-1', zh: '大阪', en: 'Osaka', lat: 34.6937, lng: 135.5023 },
    { code: 'ap-tokyo-1', zh: '东京', en: 'Tokyo', lat: 35.6762, lng: 139.6503 },
    { code: 'ap-kulai-2', zh: '古来', en: 'Kulai', lat: 1.6629, lng: 103.5999 },
    { code: 'mx-queretaro-1', zh: '克雷塔罗', en: 'Querétaro', lat: 20.5888, lng: -100.3899 },
    { code: 'mx-monterrey-1', zh: '蒙特雷', en: 'Monterrey', lat: 25.6866, lng: -100.3161 },
    { code: 'af-casablanca-1', zh: '卡萨布兰卡', en: 'Casablanca', lat: 33.5731, lng: -7.5898 },
    { code: 'eu-amsterdam-1', zh: '阿姆斯特丹', en: 'Amsterdam', lat: 52.3676, lng: 4.9041 },
    { code: 'me-riyadh-1', zh: '利雅得', en: 'Riyadh', lat: 24.7136, lng: 46.6753 },
    { code: 'me-jeddah-1', zh: '吉达', en: 'Jeddah', lat: 21.4858, lng: 39.1925 },
    { code: 'eu-jovanovac-1', zh: '乔万诺瓦茨', en: 'Jovanovac', lat: 44.0501, lng: 20.9507 },
    { code: 'ap-singapore-1', zh: '新加坡', en: 'Singapore', lat: 1.3521, lng: 103.8198 },
    { code: 'ap-singapore-2', zh: '新加坡西部', en: 'Singapore West', lat: 1.3521, lng: 103.8198 },
    { code: 'af-johannesburg-1', zh: '约翰内斯堡', en: 'Johannesburg', lat: -26.2041, lng: 28.0473 },
    { code: 'ap-seoul-1', zh: '首尔', en: 'Seoul', lat: 37.5665, lng: 126.978 },
    { code: 'ap-chuncheon-1', zh: '春川', en: 'Chuncheon', lat: 37.8747, lng: 127.7342 },
    { code: 'eu-madrid-1', zh: '马德里', en: 'Madrid', lat: 40.4168, lng: -3.7038 },
    { code: 'eu-madrid-3', zh: '马德里 3', en: 'Madrid 3', lat: 40.4168, lng: -3.7038 },
    { code: 'eu-stockholm-1', zh: '斯德哥尔摩', en: 'Stockholm', lat: 59.3293, lng: 18.0686 },
    { code: 'eu-zurich-1', zh: '苏黎世', en: 'Zurich', lat: 47.3769, lng: 8.5417 },
    { code: 'me-abudhabi-1', zh: '阿布扎比', en: 'Abu Dhabi', lat: 24.4539, lng: 54.3773 },
    { code: 'me-dubai-1', zh: '迪拜', en: 'Dubai', lat: 25.2048, lng: 55.2708 },
    { code: 'uk-london-1', zh: '伦敦', en: 'London', lat: 51.5074, lng: -0.1278 },
    { code: 'uk-cardiff-1', zh: '纽波特', en: 'Newport', lat: 51.5877, lng: -2.9984 },
    { code: 'us-ashburn-1', zh: '阿什本', en: 'Ashburn', lat: 39.0438, lng: -77.4874 },
    { code: 'us-chicago-1', zh: '芝加哥', en: 'Chicago', lat: 41.8781, lng: -87.6298 },
    { code: 'us-phoenix-1', zh: '凤凰城', en: 'Phoenix', lat: 33.4484, lng: -112.074 },
    { code: 'us-sanjose-1', zh: '圣何塞', en: 'San Jose', lat: 37.3382, lng: -121.8863 }
  ]
};
