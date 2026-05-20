import { API } from 'homebridge';
import { BMWHomePlatform } from './platform';

export default (api: API) => {
  api.registerPlatform('BMWHome', BMWHomePlatform);
};
