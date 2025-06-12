import { NativeModules } from 'react-native';

const { RNAppPushUpdate } = NativeModules;

type RNAppPushUpdateType = {
  getPushUpdateVersion: () => Promise<number>;
};

const PushUpdateModule = RNAppPushUpdate as RNAppPushUpdateType;

export const getPushUpdateVersion = async (): Promise<number> => {
  return await PushUpdateModule.getPushUpdateVersion();
};
