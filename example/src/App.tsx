import { useEffect } from 'react';
import { View, StyleSheet } from 'react-native';
import { getPushUpdateVersion } from 'react-native-app-push-update';

export default function App() {
  const version = async () => {
    const v = await getPushUpdateVersion();
    console.log(v);
  };

  useEffect(() => {
    version();
  }, []);
  return <View style={styles.container}></View>;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'red',
  },
});
