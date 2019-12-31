--
-- DVB FPGA
--
-- Copyright 2019 by Suoto <andre820@gmail.com>
--
-- This file is part of DVB FPGA.
--
-- DVB FPGA is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- DVB FPGA is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with DVB FPGA.  If not, see <http://www.gnu.org/licenses/>.

---------------
-- Libraries --
---------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.dvb_utils_pkg.all;

------------------------
-- Entity declaration --
------------------------
entity bch_encoder_mux is
  generic  ( DATA_WIDTH : integer := 8);
  port (
    clk              : in std_logic;
    rst              : in std_logic;
    --
    cfg_bch_code_in  : in  std_logic_vector(1 downto 0);
    first_word       : in std_logic; -- First data. 1: SEED is used (initialise and calculate), 0: Previous CRC is used (continue and calculate)
    wr_en            : in std_logic; -- New Data. wr_data input has a valid data. Calculate new CRC
    wr_data          : in std_logic_vector(DATA_WIDTH - 1 downto 0);  -- Data in

    --
    cfg_bch_code_out : out std_logic_vector(1 downto 0);
    crc_rdy          : out std_logic;
    crc              : out std_logic_vector(191 downto 0);
    -- Data output
    data_out         : out std_logic_vector(DATA_WIDTH - 1 downto 0));
end bch_encoder_mux;

architecture bch_encoder_mux of bch_encoder_mux is

  ---------------
  -- Constants --
  ---------------
  constant MUX_WIDTH : integer := 3;
  constant CRC_WIDTH : integer := 192;

  -----------
  -- Types --
  -----------
  type data_array_type is array(natural range <>) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  type crc_array_type is array(natural range <>) of std_logic_vector(CRC_WIDTH - 1 downto 0);

  -------------
  -- Signals --
  -------------
  signal in_mux_ptr     : integer range 0 to 2;
  signal out_mux_ptr    : integer range 0 to 2;

  signal cfg_bch_code_0 : std_logic_vector(1 downto 0);
  signal cfg_bch_code_1 : std_logic_vector(1 downto 0);
  signal wr_en_array    : std_logic_vector(MUX_WIDTH - 1 downto 0);

  signal crc_rdy_array  : std_logic_vector(MUX_WIDTH - 1 downto 0);
  signal data_out_array : data_array_type(MUX_WIDTH - 1 downto 0);
  signal crc_out_array  : crc_array_type(MUX_WIDTH - 1 downto 0);

begin

  -- Supporting other data widths might need quite a bit of work as we might need to deal
  -- with partially valid words (data + mask)
  assert DATA_WIDTH = 8
    report "Unsupported DATA_WIDTH " & integer'image(DATA_WIDTH)
    severity Failure;

  -------------------
  -- Port mappings --
  -------------------
  -- instantiate BCH blocks for DATA_WIDTH = 8
  data_width_8_gen : if DATA_WIDTH = 8 generate
    signal crc_192_ulogic      : std_ulogic_vector(191 downto 0);
    signal data_out_192_ulogic : std_ulogic_vector(7 downto 0);
    
    signal crc_160_ulogic      : std_ulogic_vector(159 downto 0);
    signal data_out_160_ulogic : std_ulogic_vector(7 downto 0);

    signal crc_128_ulogic      : std_ulogic_vector(127 downto 0);
    signal data_out_128_ulogic : std_ulogic_vector(7 downto 0);

  begin
    bch_192_u : entity work.bch_192x8
      generic map (SEED => (others => '0'))
      port map (
        clk   => clk,
        reset => rst,
        fd    => first_word,
        nd    => wr_en_array(BCH_POLY_12),
        rdy   => crc_rdy_array(BCH_POLY_12),
        d     => std_ulogic_vector(wr_data),
        c     => crc_192_ulogic,
        -- CRC output
        o     => data_out_192_ulogic);

    bch_160_u : entity work.bch_160x8
      generic map (SEED => (others => '0'))
      port map (
        clk   => clk,
        reset => rst,
        fd    => first_word,
        nd    => wr_en_array(BCH_POLY_10),
        rdy   => crc_rdy_array(BCH_POLY_10),
        d     => std_ulogic_vector(wr_data),
        c     => crc_160_ulogic,
        -- CRC output
        o     => data_out_160_ulogic);

    bch_128_u : entity work.bch_128x8
      generic map (SEED => (others => '0'))
      port map (
        clk   => clk,
        reset => rst,
        fd    => first_word,
        nd    => wr_en_array(BCH_POLY_8),
        rdy   => crc_rdy_array(BCH_POLY_8),
        d     => std_ulogic_vector(wr_data),
        c     => crc_128_ulogic,
        -- CRC output
        o     => data_out_128_ulogic);

    -- Assign vector outpus
    crc_out_array(BCH_POLY_12)               <= std_logic_vector(crc_192_ulogic);
    data_out_array(BCH_POLY_12)              <= std_logic_vector(data_out_192_ulogic);

    crc_out_array(BCH_POLY_10)(159 downto 0) <= std_logic_vector(crc_160_ulogic);
    data_out_array(BCH_POLY_10)              <= std_logic_vector(data_out_160_ulogic);

    crc_out_array(BCH_POLY_8)(127 downto 0)  <= std_logic_vector(crc_128_ulogic);
    data_out_array(BCH_POLY_8)               <= std_logic_vector(data_out_128_ulogic);

  end generate;

  ------------------------------
  -- Asynchronous assignments --
  ------------------------------
  cfg_bch_code_out         <= cfg_bch_code_1;

  in_mux_ptr               <= to_integer(unsigned(cfg_bch_code_in));
  out_mux_ptr              <= to_integer(unsigned(cfg_bch_code_1));

  wr_en_array(BCH_POLY_8)  <= wr_en when in_mux_ptr = BCH_POLY_8 else '0';
  wr_en_array(BCH_POLY_10) <= wr_en when in_mux_ptr = BCH_POLY_10 else '0';
  wr_en_array(BCH_POLY_12) <= wr_en when in_mux_ptr = BCH_POLY_12 else '0';

  crc_rdy                  <= crc_rdy_array(out_mux_ptr);
  crc                      <= crc_out_array(out_mux_ptr);
  data_out                 <= data_out_array(out_mux_ptr);

  ---------------
  -- Processes --
  ---------------
  process(clk, rst)
  begin
    if rst = '1' then
      cfg_bch_code_0 <= (others => '0');
      cfg_bch_code_1 <= (others => '0');
    elsif rising_edge(clk) then
      -- Sample the input code whenever the first word is written
      if wr_en = '1' and first_word = '1' then
        cfg_bch_code_0 <= cfg_bch_code_in;
      end if;

      -- Output it when CRC calc is complete
      if crc_rdy_array(to_integer(unsigned(cfg_bch_code_0))) = '1' then
        cfg_bch_code_1 <= cfg_bch_code_0;
      end if;
    end if;
  end process;


end bch_encoder_mux;