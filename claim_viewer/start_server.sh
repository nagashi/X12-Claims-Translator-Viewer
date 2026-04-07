#!/bin/bash
#*******************************************************************************#
#										#
#
# Define the shell functions
#
usage(){
	echo "Usage: $0 [-h]" >&2
	exit 0
}

die()
{
	echo "$1" >&2
	exit 1
}

#
# Get command line options
#
while getopts ":h" opt; do
	  case $opt in
	          h) usage
			 ;;
		 \?) die "Error---->Invalid option: -$OPTARG"
		         ;;
	  esac
done

# Configure the kill actions to take
trap "echo $0: killed @ $(date) ; exit 99" SIGHUP SIGINT SIGTERM

#
# Detect the operating system
#
OS=$(uname -s 2>/dev/null || echo "Unknown")

# Script starts here
# Provide the script name, who, when, and where
#
echo "Script $0: was run by $(whoami) at $(date) on server $(hostname)"

#
# Get OS info and IP address based on detected OS
#
case "$OS" in
	Darwin)
		echo "Server OS info is: $(sw_vers | tr '\n' '  ')"
		IP=$(ipconfig getifaddr en0 2>/dev/null)
		[ -z "$IP" ] && IP=$(ipconfig getifaddr en1 2>/dev/null)
		[ -z "$IP" ] && IP="Unknown"
		echo "IP Address: $IP"
		;;
	Linux)
		echo "Server OS info is: $(cat /proc/version)"
		IP=$(ifconfig 2>/dev/null | grep "inet addr" | head -1 | sed 's/Bcast//' | awk -F\: '{print $2;}' | awk '{print $1}')
		[ -z "$IP" ] && IP=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
		[ -z "$IP" ] && IP="Unknown"
		echo "IP Address: $IP"
		;;
	MINGW*|CYGWIN*|MSYS*)
		echo "Server OS info is: Windows (Running via $(uname -s))"
		echo "NOTE: Ensure Elixir and PostgreSQL are installed and accessible in this environment."
		IP=$(ipconfig 2>/dev/null | grep "IPv4" | head -1 | awk -F: '{print $2}' | tr -d ' \r')
		[ -z "$IP" ] && IP="Unknown"
		echo "IP Address: $IP"
		;;
	*)
		echo "Server OS info is: $OS $(uname -r 2>/dev/null)"
		IP=$(hostname -I 2>/dev/null | awk '{print $1}')
		[ -z "$IP" ] && IP="Unknown"
		echo "IP Address: $IP"
		;;
esac

# Main body starts here....
#
# cd to home directory
#
cd "$HOME" || die "Error----> Cannot change to home directory."

# Remove the old directory
rm -rf X12-Claims-Translator-Viewer

# Download the source code git repository
git clone https://github.com/nagashi/X12-Claims-Translator-Viewer.git || die "Error----> Git clone failed."

cd X12-Claims-Translator-Viewer/claim_viewer || die "Error----> Cannot change to claim_viewer directory."

# 1. Install dependencies
mix deps.get || die "Error----> mix deps.get failed."

# 2. Setup database and assets
mix setup || die "Error----> mix setup failed."

# Full suite: 58 unit tests + 69 property-based tests
echo ""
echo "Running test suite..."
echo "==============================="
TEST_OUTPUT=$(mix test 2>&1)
echo "$TEST_OUTPUT"

# Parse the ExUnit summary line, e.g. "127 tests, 0 failures" or "127 tests, 3 failures"
SUMMARY_LINE=$(echo "$TEST_OUTPUT" | grep -E "^[0-9]+ tests?,")
TOTAL=$(echo "$SUMMARY_LINE" | grep -oE '^[0-9]+')
FAILURES=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ failure' | grep -oE '^[0-9]+')

[ -z "$TOTAL" ]    && TOTAL=0
[ -z "$FAILURES" ] && FAILURES=0
PASSED=$((TOTAL - FAILURES))

echo "==============================="
echo "Test Results Summary:"
echo "  Tests Passed : $PASSED"
echo "  Tests Failed : $FAILURES"
echo "==============================="
echo ""

# 3. Start the server
mix phx.server

exit 0
