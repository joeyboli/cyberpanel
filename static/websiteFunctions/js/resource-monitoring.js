// Resource Monitoring with ApexCharts
let cpuChart, memoryChart, diskChart;
let cpuData = [], memoryData = [], diskData = [];
const maxDataPoints = 20;

function createChartOptions(label, color, height) {
    return {
        series: [{
            name: label,
            data: []
        }],
        chart: {
            type: 'area',
            height: height,
            toolbar: { show: false },
            zoom: { enabled: false },
            animations: {
                enabled: true,
                easing: 'linear',
                dynamicAnimation: { speed: 1000 }
            },
            sparkline: { enabled: false }
        },
        colors: [color],
        dataLabels: { enabled: false },
        stroke: { curve: 'smooth', width: 2 },
        fill: {
            type: 'gradient',
            gradient: {
                shadeIntensity: 1,
                opacityFrom: 0.4,
                opacityTo: 0.1,
                stops: [0, 90, 100]
            }
        },
        grid: {
            borderColor: 'rgba(144, 144, 144, 0.05)',
            padding: { left: 0, right: 0 }
        },
        xaxis: {
            type: 'datetime',
            range: 100000, // Show last 100 seconds
            labels: { show: false },
            axisBorder: { show: false },
            axisTicks: { show: false }
        },
        yaxis: {
            max: 100,
            min: 0,
            tickAmount: 4,
            labels: {
                style: { colors: '#888', fontSize: '10px' },
                formatter: (val) => val.toFixed(0) + '%'
            }
        },
        tooltip: {
            theme: 'dark',
            x: { format: 'HH:mm:ss' }
        }
    };
}

function initializeCharts() {
    if (!document.getElementById('cpuChart')) return;

    cpuChart = new ApexCharts(document.querySelector("#cpuChart"), createChartOptions('CPU', '#3b82f6', 250));
    memoryChart = new ApexCharts(document.querySelector("#memoryChart"), createChartOptions('Memory', '#10b981', 250));
    diskChart = new ApexCharts(document.querySelector("#diskChart"), createChartOptions('Disk', '#f59e0b', 250));

    cpuChart.render();
    memoryChart.render();
    diskChart.render();
}

function updateCharts(data) {
    const now = new Date().getTime();

    cpuData.push({ x: now, y: data.cpu_usage });
    memoryData.push({ x: now, y: data.memory_usage });
    diskData.push({ x: now, y: data.disk_percent });

    if (cpuData.length > maxDataPoints) cpuData.shift();
    if (memoryData.length > maxDataPoints) memoryData.shift();
    if (diskData.length > maxDataPoints) diskData.shift();

    if (cpuChart) cpuChart.updateSeries([{ data: cpuData }]);
    if (memoryChart) memoryChart.updateSeries([{ data: memoryData }]);
    if (diskChart) diskChart.updateSeries([{ data: diskData }]);
}

function fetchResourceUsage() {
    const domain = $('#domainNamePage').text().trim();
    if (!domain) return;

    $.ajax({
        url: '/websites/get_website_resources/',
        type: 'POST',
        data: JSON.stringify({ 'domain': domain }),
        contentType: 'application/json',
        success: function(data) {
            if (data.status === 1) {
                updateCharts(data);
            }
        },
        error: function(xhr, status, error) {
            console.error('Failed to fetch resource usage:', error);
        }
    });
}

$(document).ready(function() {
    initializeCharts();
    if (document.getElementById('cpuChart')) {
        setInterval(fetchResourceUsage, 5000);
        fetchResourceUsage();
    }
});
