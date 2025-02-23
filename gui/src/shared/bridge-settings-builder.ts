import { BridgeSettings, IBridgeConstraints } from './daemon-rpc-types';
import makeLocationBuilder, { ILocationBuilder } from './relay-location-builder';

export default class BridgeSettingsBuilder {
  private payload: Partial<IBridgeConstraints> = {};

  public build(): BridgeSettings {
    if (this.payload.location) {
      return {
        normal: {
          location: this.payload.location,
          providers: this.payload.providers ?? [],
        },
      };
    } else {
      throw new Error('Unsupported configuration');
    }
  }

  get location(): ILocationBuilder<BridgeSettingsBuilder> {
    return makeLocationBuilder(this, (location) => {
      this.payload.location = location;
    });
  }
}
