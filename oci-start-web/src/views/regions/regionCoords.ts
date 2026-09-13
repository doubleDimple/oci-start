export const REGION_COORDINATES: Record<string, { lat: number; lng: number }> = {
  'af-johannesburg-1': { lat: -26.2041, lng: 28.0473 },
  'af-casablanca-1': { lat: 33.5731, lng: -7.5898 },
  'ap-chuncheon-1': { lat: 37.8747, lng: 127.7342 },
  'ap-hyderabad-1': { lat: 17.385, lng: 78.4867 },
  'ap-melbourne-1': { lat: -37.8136, lng: 144.9631 },
  'ap-mumbai-1': { lat: 19.076, lng: 72.8777 },
  'ap-osaka-1': { lat: 34.6937, lng: 135.5023 },
  'ap-seoul-1': { lat: 37.5665, lng: 126.978 },
  'ap-kulai-2': { lat: 1.6629, lng: 103.5999 },
  'ap-singapore-1': { lat: 1.3521, lng: 103.8198 },
  'ap-singapore-2': { lat: 1.3, lng: 103.75 },
  'ap-sydney-1': { lat: -33.8688, lng: 151.2093 },
  'ap-tokyo-1': { lat: 35.6762, lng: 139.6503 },
  'ap-batam-1': { lat: 1.1074, lng: 104.03 },
  'ca-montreal-1': { lat: 45.5017, lng: -73.5673 },
  'ca-toronto-1': { lat: 43.6532, lng: -79.3832 },
  'eu-amsterdam-1': { lat: 52.3676, lng: 4.9041 },
  'eu-frankfurt-1': { lat: 50.1109, lng: 8.6821 },
  'eu-jovanovac-1': { lat: 44.2768, lng: 20.5896 },
  'eu-madrid-1': { lat: 40.4168, lng: -3.7038 },
  'eu-madrid-3': { lat: 40.4168, lng: -3.7038 },
  'eu-marseille-1': { lat: 43.2965, lng: 5.3698 },
  'eu-milan-1': { lat: 45.4642, lng: 9.19 },
  'eu-turin-1': { lat: 45.0703, lng: 7.6869 },
  'eu-paris-1': { lat: 48.8566, lng: 2.3522 },
  'eu-stockholm-1': { lat: 59.3293, lng: 18.0686 },
  'eu-zurich-1': { lat: 47.3769, lng: 8.5417 },
  'il-jerusalem-1': { lat: 31.7683, lng: 35.2137 },
  'me-abudhabi-1': { lat: 24.4539, lng: 54.3773 },
  'me-dubai-1': { lat: 25.2048, lng: 55.2708 },
  'me-jeddah-1': { lat: 21.4858, lng: 39.1925 },
  'me-riyadh-1': { lat: 24.7136, lng: 46.6753 },
  'mx-monterrey-1': { lat: 25.6866, lng: -100.3161 },
  'mx-queretaro-1': { lat: 20.5888, lng: -100.3899 },
  'sa-bogota-1': { lat: 4.711, lng: -74.0721 },
  'sa-santiago-1': { lat: -33.4489, lng: -70.6693 },
  'sa-saopaulo-1': { lat: -23.5505, lng: -46.6333 },
  'sa-vinhedo-1': { lat: -23.0304, lng: -46.9834 },
  'uk-cardiff-1': { lat: 51.4816, lng: -3.1791 },
  'uk-london-1': { lat: 51.5074, lng: -0.1278 },
  'us-ashburn-1': { lat: 39.0438, lng: -77.4874 },
  'us-chicago-1': { lat: 41.8781, lng: -87.6298 },
  'us-phoenix-1': { lat: 33.4484, lng: -112.074 },
  'us-sanjose-1': { lat: 37.3382, lng: -121.8863 },
  'sa-valparaiso-1': { lat: -33.0472, lng: -71.6127 },
}

export const CONTINENT_MAP: Record<string, string> = {
  'ap-': 'asia',
  'eu-': 'europe',
  'uk-': 'europe',
  'il-': 'europe',
  'me-': 'middle-east',
  'af-': 'middle-east',
  'us-': 'america-north',
  'ca-': 'america-north',
  'mx-': 'america-north',
  'sa-': 'america-south',
}

// Display city names for the fixed map locations; identifiers remain unchanged.
export function englishRegionName(code: string) {
  if (!REGION_COORDINATES[code]) return code
  const city = code.split('-').slice(1, -1).join(' ')
  const names: Record<string, string> = {
    abudhabi: 'Abu Dhabi', sanjose: 'San Jose', saopaulo: 'São Paulo',
    valparaiso: 'Valparaíso', queretaro: 'Querétaro',
  }
  return names[city] || city.replace(/\b\w/g, letter => letter.toUpperCase())
}

// Short city labels keep map pins readable; full server region names stay in details.
export function regionCityName(code: string, locale: string) {
  if (!locale.startsWith('zh')) return englishRegionName(code)
  const city = code.split('-').slice(1, -1).join(' ')
  const names: Record<string, string> = {
    johannesburg: '约翰内斯堡', casablanca: '卡萨布兰卡', chuncheon: '春川',
    hyderabad: '海得拉巴', melbourne: '墨尔本', mumbai: '孟买', osaka: '大阪', seoul: '首尔',
    kulai: '古来', singapore: '新加坡', sydney: '悉尼', tokyo: '东京', batam: '巴淡',
    montreal: '蒙特利尔', toronto: '多伦多', amsterdam: '阿姆斯特丹', frankfurt: '法兰克福',
    jovanovac: '乔万诺瓦茨', madrid: '马德里', marseille: '马赛', milan: '米兰', turin: '都灵',
    paris: '巴黎', stockholm: '斯德哥尔摩', zurich: '苏黎世', jerusalem: '耶路撒冷',
    abudhabi: '阿布扎比', dubai: '迪拜', jeddah: '吉达', riyadh: '利雅得',
    monterrey: '蒙特雷', queretaro: '克雷塔罗', bogota: '波哥大', santiago: '圣地亚哥',
    saopaulo: '圣保罗', vinhedo: '维涅杜', cardiff: '加的夫', london: '伦敦',
    ashburn: '阿什本', chicago: '芝加哥', phoenix: '凤凰城', sanjose: '圣何塞', valparaiso: '瓦尔帕莱索',
  }
  return names[city] || code
}

export function getContinent(regionCode: string) {
  for (const prefix in CONTINENT_MAP) {
    if (regionCode.startsWith(prefix)) return CONTINENT_MAP[prefix]
  }
  return 'other'
}
