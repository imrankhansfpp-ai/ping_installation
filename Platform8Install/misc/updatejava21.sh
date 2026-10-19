#!/bin/bash

# Check current Java version
echo "Current Java version:"
java -version

# Step 1: Remove existing Java (only if installed via rpm/yum)
echo "Removing existing Java packages..."
sudo dnf remove -y java-*-openjdk

# Step 2: Enable EPEL if not already
echo "Enabling EPEL repository..."
sudo dnf install -y epel-release

# Step 3: Install OpenJDK 21
echo "Installing OpenJDK 21..."
sudo dnf install -y java-21-openjdk java-21-openjdk-devel

# Step 4: Set Java 21 as the default
echo "Setting Java 21 as the default..."
sudo alternatives --install /usr/bin/java java /usr/lib/jvm/java-21-openjdk-*/bin/java 221
sudo alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-21-openjdk-*/bin/javac 221
sudo alternatives --set java /usr/lib/jvm/java-21-openjdk-*/bin/java
sudo alternatives --set javac /usr/lib/jvm/java-21-openjdk-*/bin/javac

# Step 5: Confirm installation
echo "Updated Java version:"
java -version

