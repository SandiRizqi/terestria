FROM python:3.10-slim

# Install GDAL dan dependencies + zip
RUN apt-get update && apt-get install -y gdal-bin libgdal-dev python3-gdal zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install library Python tambahan
RUN pip install numpy pillow

# Cek versi GDAL dan Python
RUN gdalinfo --version && python3 --version

# Cek lokasi Python binary dan library
RUN which python3 && ls -R /usr/local/lib | grep python

# Buat folder output dan kompres runtime Python
RUN mkdir -p /out && cd /usr/local/lib && zip -r /out/python_runtime.zip python3.10
