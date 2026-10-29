# Build và chạy API trên Render (render.yaml trỏ tới file này, thư mục build là server/)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY DiemDanhApi/DiemDanhApi.csproj DiemDanhApi/
RUN dotnet restore DiemDanhApi/DiemDanhApi.csproj
COPY DiemDanhApi/ DiemDanhApi/
RUN dotnet publish DiemDanhApi/DiemDanhApi.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_ENVIRONMENT=Production
# Render báo cổng cần mở qua biến PORT
CMD ASPNETCORE_HTTP_PORTS=${PORT:-8080} dotnet DiemDanhApi.dll
