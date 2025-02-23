import React from 'react';
import styled from 'styled-components';
import { supportEmail } from '../../config.json';
import { messages } from '../../shared/gettext';
import log from '../../shared/logging';
import PlatformWindowContainer from '../containers/PlatformWindowContainer';
import ErrorView from './ErrorView';

interface IProps {
  children?: React.ReactNode;
}

interface IState {
  hasError: boolean;
}

const Email = styled.span({
  fontWeight: 900,
});

export default class ErrorBoundary extends React.Component<IProps, IState> {
  public state = { hasError: false };

  public componentDidCatch(error: Error, info: React.ErrorInfo) {
    this.setState({ hasError: true });

    log.error(
      `The error boundary caught an error: ${error.message}\nError stack: ${
        error.stack || 'Not available'
      }\nComponent stack: ${info.componentStack}`,
    );
  }

  public render() {
    if (this.state.hasError) {
      const reachBackMessage: React.ReactNodeArray =
        // TRANSLATORS: The message displayed to the user in case of critical error in the GUI
        // TRANSLATORS: Available placeholders:
        // TRANSLATORS: %(email)s - support email
        messages
          .pgettext('error-boundary-view', 'Something went wrong. Please contact us at %(email)s')
          .split('%(email)s', 2);
      reachBackMessage.splice(1, 0, <Email>{supportEmail}</Email>);

      return (
        <PlatformWindowContainer>
          <ErrorView>{reachBackMessage}</ErrorView>
        </PlatformWindowContainer>
      );
    } else {
      return this.props.children;
    }
  }
}
