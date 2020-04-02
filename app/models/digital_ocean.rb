module DigitalOcean
  class Droplet < Struct.new(:id, :name, :created_at, :memory, :status, :snapshot_ids, :ipv4)
  end

  class Image < Struct.new(:id, :name, :created_at)
  end

  class SSHKey < Struct.new(:id, :name, :fingerprint, :public_key)
  end

  class Action < Struct.new(:id, :status)
    def done?
      status == 'completed'
    end
    def failed?
      status == 'errored'
    end
  end

  class Size < Struct.new(:slug, :name, :memory, :disk, :cpu, :price_hourly, :price_monthly)
    DEFAULT_SIZES = [
      { price_hourly: 0.00744, price_monthly: 5.0, cpu: 1, disk: 20, memory: 512, name: '512MB', slug: '512mb' },
      { price_hourly: 0.01488, price_monthly: 10.0, cpu: 1, disk: 30, memory: 1024, name: '1GB', slug: '1gb' },
      { price_hourly: 0.02976, price_monthly: 20.0, cpu: 2, disk: 40, memory: 2048, name: '2GB', slug: '2gb' },
      { price_hourly: 0.05952, price_monthly: 40.0, cpu: 2, disk: 60, memory: 4096, name: '4GB', slug: '4gb' },
      { price_hourly: 0.11905, price_monthly: 80.0, cpu: 4, disk: 80, memory: 8192, name: '8GB', slug: '8gb' },
      { price_hourly: 0.2381, price_monthly: 160.0, cpu: 8, disk: 160, memory: 16384, name: '16GB', slug: '16gb' },
      { price_hourly: 0.47619, price_monthly: 320.0, cpu: 12, disk: 320, memory: 32768, name: '32GB', slug: '32gb' },
      { price_hourly: 0.71429, price_monthly: 480.0, cpu: 16, disk: 480, memory: 49152, name: '48GB', slug: '48gb' },
      { price_hourly: 0.95238, price_monthly: 640.0, cpu: 20, disk: 640, memory: 65536, name: '64GB', slug: '64gb' }
    ].map do |x|
      Size.new(x[:slug], x[:name], x[:memory], x[:disk], x[:cpu], x[:price_hourly], x[:price_monthly])
    end
    def price
      "#{(price_hourly * 100).round(1)} cents/hour"
    end
    def descriptor
      "#{name} at #{price} (up to $#{price_monthly}/month)"
    end
  end

  class Region < Struct.new(:slug, :name, :available)
    DEFAULT_REGIONS = [
      { name: 'New York 3', slug: 'nyc3' },
      { name: 'Amsterdam 3', slug: 'ams3' },
      { name: 'New York 2', slug: 'nyc2' },
      { name: 'Amsterdam 2', slug: 'ams2' },
      { name: 'San Francisco 1', slug: 'sfo1' },
      { name: 'London 1', slug: 'lon1' },
      { name: 'Singapore 1', slug: 'sgp1' },
    ].map { |x| Region.new(x[:slug], x[:name], true) }
  end

  class Connection
    OPEN_TIMEOUT = 32
    TIMEOUT = 64
    def initialize(api_key)
      @con = DropletKit::Client.new(access_token: api_key, open_timeout: OPEN_TIMEOUT, timeout: TIMEOUT)
    end

    def droplet_list
      silence do
        @con.droplets.all.map { |x| self.class.droplet_from_response(x) }
      end
    end

    def droplet_show(id)
      silence do
        self.class.droplet_from_response(@con.droplets.find(id: id))
      end
    end

    def droplet_action_list(id)
      silence do
        @con.droplets.actions(id: id).map { |x| self.class.action_from_response(x) }.sort { |a, b| a.id <=> b.id }
      end
    end

    def droplet_create(name, region, size, image, ssh_keys)
      silence do
        droplet = DropletKit::Droplet.new(
          name: name,
          region: region,
          size: size,
          image: image,
          ssh_keys: ssh_keys.map { |x| x.to_s },
        )
        self.class.droplet_from_response(@con.droplets.create(droplet))
      end
    end

    def droplet_snapshot(id, name)
      silence do
        action = @con.droplet_actions.snapshot(droplet_id: id, name: name)
        self.class.action_from_response(action)
      end
    end

    def droplet_delete(id)
      silence do
        @con.droplets.delete(id: id)
        nil
      end
    end

    def droplet_shutdown(id)
      silence do
        action = @con.droplet_actions.shutdown(droplet_id: id)
        self.class.action_from_response(action)
      end
    end

    def droplet_reboot(id)
      silence do
        action = @con.droplet_actions.reboot(droplet_id: id)
        self.class.action_from_response(action)
      end
    end

    def droplet_action_show(droplet_id, action_id)
      silence do
        action = @con.droplet_actions.find(droplet_id: droplet_id, id: action_id)
        self.class.action_from_response(action)
      end
    end

    def image_list(private_only = true)
      silence do
        @con.images.all(private: private_only).map { |x| self.class.image_from_response(x) }
      end
    end

    def image_delete(id)
      silence do
        @con.images.delete(id: id)
        nil
      end
    end

    def ssh_key_list
      silence do
        @con.ssh_keys.all.map { |x| self.class.ssh_key_from_response(x) }
      end
    end

    def ssh_key_show(id)
      silence do
        self.class.ssh_key_from_response(@con.ssh_keys.find(id: id))
      end
    end

    def ssh_key_create(name, public_key)
      silence do
        key = DropletKit::SSHKey.new(
          name: name,
          public_key: public_key,
        )
        self.class.ssh_key_from_response(@con.ssh_keys.create(key))
      end
    end

    def ssh_key_delete(id)
      silence do
        @con.ssh_keys.delete(id: id)
        nil
      end
    end

    def region_list_uncached
      silence do
        @con.regions.all.map { |x| self.class.region_from_response(x) }.sort do |a, b|
          a_tier = a.slug[-1].to_i
          b_tier = b.slug[-1].to_i
          a_tier == b_tier ? a.slug <=> b.slug : b_tier <=> a_tier
        end
      end
    end

    def size_list_uncached
      silence do
        @con.sizes.all.map { |x| self.class.size_from_response(x) }.select { |x| [ 's', 'c'].include?(x.slug[0] ) }
      end
    end

    def region_list
      if @regions.nil?
        res = region_list_uncached
        if res.error?
          Rails.logger.error "Unable to get Digital Ocean regions in #{self.class}: #{res}"
          @regions = DigitalOcean::Region::DEFAULT_REGIONS
        else
          @regions = res.select { |x| x.available }
        end
      end
      return @regions
    end

    def size_list
      if @sizes.nil?
        res = size_list_uncached
        if res.error?
          Rails.logger.error "Unable to get Digital Ocean sizes in #{self.class}: #{res}"
          @sizes = DigitalOcean::Size::DEFAULT_SIZES
        else
          @sizes = res
        end
      end
      return @sizes
    end

    def region_find(slug)
      for x in region_list
        if x.slug == slug
          return x
        end
      end
      return nil
    end

    def size_find(slug)
      for x in size_list
        if x.slug == slug
          return x
        end
      end
      for x in Size::DEFAULT_SIZES
        if x.slug == slug
          return x
        end
      end
      return nil
    end

    def self.droplet_from_response(res)
      Droplet.new(res.id,
        res.name,
        res.created_at,
        res.memory,
        res.status,
        res.snapshot_ids.sort,
        res.networks.v4.try(:select) { |x| x.type == 'public' }.try(:first).try(:ip_address),
      )
    end

    def self.image_from_response(res)
      Image.new(res.id, res.name, res.created_at)
    end

    def self.action_from_response(res)
      Action.new(res.id, res.status)
    end

    def self.ssh_key_from_response(res)
      SSHKey.new(res.id, res.name, res.fingerprint, res.public_key)
    end

    def self.size_from_response(res)
      Size.new(res.slug, res.slug.upcase, res.memory, res.disk, res.vcpus, res.price_hourly, res.price_monthly)
    end

    def self.region_from_response(res)
      Region.new(res.slug, res.name, res.available)
    end
  end
end
